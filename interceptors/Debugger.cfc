/**
 * Coldbox Debugger Interecptor
 */
component extends="coldbox.system.Interceptor" {

	/**
	 * Configure
	 */
	function configure(){
		variables.debuggerService = getInstance( "debuggerService@cbdebugger" );
		variables.debuggerConfig  = controller.getSetting( "debugger" );
	}

	// Before we capture.
	function onRequestCapture( event, interceptData, rc, prc ){
		// init tracker
		request.cbdebugger = {};
		request.fwExecTime = getTickCount();

		// Debug Mode Checks
		if ( structKeyExists( rc, "debugMode" ) AND isBoolean( rc.debugMode ) ) {
			if ( NOT len( variables.debuggerConfig.debugPassword ) ) {
				debuggerService.setDebugMode( rc.debugMode );
			} else if (
				structKeyExists( rc, "debugPassword" ) AND compareNoCase(
					variables.debuggerConfig.debugPassword,
					hash( rc.debugPassword )
				) eq 0
			) {
				debuggerService.setDebugMode( rc.debugMode );
			}
		}

		// verify in debug mode
		if ( debuggerService.getDebugMode() ) {
			// call debug commands
			debuggerCommands( arguments.event );
			// panel rendering
			var debugPanel = event.getValue( "debugPanel", "" );

			switch ( debugPanel ) {
				case "profiler": {
					writeOutput( debuggerService.renderProfiler() );
					break;
				}
				case "cache":
				case "cacheReport":
				case "cacheContentReport":
				case "cacheViewer": {
					writeOutput( debuggerService.renderCachePanel() );
					break;
				}
			}
			// turn off debugger and stop
			if ( len( debugPanel ) ) {
				include "/cbdebugger/includes/debugoutput.cfm";
				abort;
			}
		}
	}

	// setup all the timers
	public function preProcess( event, interceptData, rc, prc ){
		request.cbdebugger.processHash = debuggerService.timerStart(
			"[preProcess to postProcess] for #arguments.event.getCurrentEvent()#"
		);
	}

	// post processing
	public function postProcess(
		event,
		interceptData,
		rc,
		prc,
		buffer
	){
		var debugHTML = "";
		var command   = event.getTrimValue( "cbox_command", "" );

		// Verify if we have a command, if we do just exit
		if ( len( command ) ) {
			return;
		}

		// end the request timer
		debuggerService.timerEnd( isNull( request.cbdebugger.processHash ) ? "" : request.cbdebugger.processHash );
		request.fwExecTime = getTickCount() - request.fwExecTime;
		// record the profilers
		debuggerService.recordProfiler();
		// Only render if enabled, if no renderdata, and if not ajax call and not in testing mode
		if (
			debuggerService.getDebugMode() AND
			isDebuggerRendering() AND
			structIsEmpty( event.getRenderData() ) AND
			!event.isAjax() AND
			!findNoCase( "MockController", getMetadata( controller ).name )
		) {
			// render out the debugger
			debugHTML = debuggerService.renderDebugLog();
			// render out the debugger to output
			buffer.append( debugHTML );
		}
	}

	public function preEvent( event, interceptData, rc, prc ){
		request.cbdebugger.eventhash = debuggerService.timerStart(
			"[preEvent to postEvent] for #arguments.event.getCurrentEvent()#"
		);
	}

	public function postEvent( event, interceptData, rc, prc ){
		debuggerService.timerEnd( request.cbdebugger.eventhash );
	}

	public function preLayout( event, interceptData, rc, prc ){
		request.cbdebugger.layoutHash = debuggerService.timerStart(
			"[preLayout to postLayout] for #arguments.event.getCurrentEvent()#"
		);
	}

	public function postLayout( event, interceptData, rc, prc ){
		debuggerService.timerEnd( request.cbdebugger.layoutHash );
	}

	public function preRender( event, interceptData, rc, prc ){
		request.cbdebugger.renderHash = debuggerService.timerStart(
			"[preRender to postRender] for #arguments.event.getCurrentEvent()#"
		);
	}

	public function postRender( event, interceptData, rc, prc ){
		debuggerService.timerEnd( request.cbdebugger.renderHash );
	}

	public function preViewRender( event, interceptData, rc, prc ){
		request.cbdebugger.renderViewHash = debuggerService.timerStart(
			"Rendering View: #interceptData.view# from event: #arguments.event.getCurrentEvent()#"
		);
	}

	public function postViewRender( event, interceptData, rc, prc ){
		debuggerService.timerEnd( request.cbdebugger.renderViewHash );
	}

	public function preLayoutRender( event, interceptData, rc, prc ){
		request.cbdebugger.layoutHash = debuggerService.timerStart(
			"Rendering Layout: #interceptData.layout# from event: #arguments.event.getCurrentEvent()#"
		);
	}

	public function postLayoutRender( event, interceptData, rc, prc ){
		debuggerService.timerEnd( request.cbdebugger.layoutHash );
	}

	public function beforeInstanceCreation( event, interceptData, rc, prc ){
		if ( variables.debuggerConfig.wireboxCreationProfiler ) {
			request.cbdebugger[ interceptData.mapping.getName() ] = debuggerService.timerStart(
				"Wirebox instance creation of #interceptData.mapping.getName()#"
			);
		}
	}

	public function afterInstanceCreation( event, interceptData, rc, prc ){
		// so many checks, due to chicken and the egg problems
		if (
			variables.debuggerConfig.wireboxCreationProfiler
			and structKeyExists( request, "cbdebugger" )
			and structKeyExists( request.cbdebugger, interceptData.mapping.getName() )
		) {
			debuggerService.timerEnd( request.cbdebugger[ interceptData.mapping.getName() ] );
		}
	}

	/************************************** PRIVATE METHODS *********************************************/

	/**
	 * Debugger Commands
	 */
	private function debuggerCommands( event ){
		var command = event.getTrimValue( "cbox_command", "" );
		var results = "";

		// Verify command
		if ( NOT len( command ) ) {
			return;
		}

		// Commands
		switch ( command ) {
			// Module Commands
			case "reloadModules": {
				controller.getModuleService().reloadAll();
				break;
			}
			case "unloadModules": {
				controller.getModuleService().unloadAll();
				break;
			}
			case "reloadModule": {
				controller.getModuleService().reload( event.getValue( "module", "" ) );
				break;
			}
			case "unloadModule": {
				controller.getModuleService().unload( event.getValue( "module", "" ) );
				break;
			}
			// Caching Reporting Commands
			case "expirecache":
			case "reapcache":
			case "delcacheentry":
			case "expirecacheentry":
			case "clearallevents":
			case "clearallviews":
			case "cacheBoxReapAll":
			case "cacheBoxExpireAll":
			case "gc": {
				debuggerService.renderCachePanel();
				break;
			}
			default:
				return;
		}

		// relocate to correct panel
		if ( event.getValue( "debugPanel", "" ) eq "" ) {
			relocate( URL = "#listLast( cgi.script_name, "/" )#", addtoken = false );
		} else {
			relocate(
				URL      = "#listLast( cgi.script_name, "/" )#?debugpanel=#event.getValue( "debugPanel", "" )#",
				addtoken = false
			);
		}
	}

}
