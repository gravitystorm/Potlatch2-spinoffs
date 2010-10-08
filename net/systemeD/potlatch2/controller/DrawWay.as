package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.geom.*;
	import flash.display.DisplayObject;
	import flash.ui.Keyboard;
	import net.systemeD.potlatch2.EditController;
	import net.systemeD.halcyon.connection.*;
    import net.systemeD.halcyon.connection.actions.*;
	import net.systemeD.halcyon.Elastic;
	import net.systemeD.halcyon.Globals;
	import net.systemeD.halcyon.MapPaint;

	public class DrawWay extends SelectedWay {
		private var elastic:Elastic;
		private var editEnd:Boolean;
		private var leaveNodeSelected:Boolean;
		private var lastClick:Entity=null;
		private var lastClickTime:Date;
		private var hoverEntity:Entity;			// keep track of the currently rolled-over object, because
												// Flash can fire a mouseDown from the map even if you
												// haven't rolled out of the way
		
		public function DrawWay(way:Way, editEnd:Boolean, leaveNodeSelected:Boolean) {
			super(way);
			this.editEnd = editEnd;
			this.leaveNodeSelected = leaveNodeSelected;
			if (way.length==1 && way.getNode(0).parentWays.length==1) {
				// drawing new way, so keep track of click in case creating a POI
				lastClick=way.getNode(0);
				lastClickTime=new Date();
			}
            way.addEventListener(Connection.WAY_NODE_REMOVED, fixElastic);
            way.addEventListener(Connection.WAY_NODE_ADDED, fixElastic);
		}
		
		override public function processMouseEvent(event:MouseEvent, entity:Entity):ControllerState {
			var mouse:Point;
			var node:Node;
			var paint:MapPaint = getMapPaint(DisplayObject(event.target));
			var isBackground:Boolean = paint && paint.isBackground;

			if (entity == null && hoverEntity) { entity=hoverEntity; }
			var focus:Entity = getTopLevelFocusEntity(entity);

			if ( event.type == MouseEvent.MOUSE_UP ) {
                controller.map.mouseUpHandler(); // in case you're still in the drag-tolerance zone, and mouse up over something.
				if ( entity == null || isBackground ) {
					node = createAndAddNode(event, MainUndoStack.getGlobalStack().addAction);
                    controller.map.setHighlight(node, { selectedway: true });
                    controller.map.setPurgable(node, false);
					resetElastic(node);
					lastClick=node;
				} else if ( entity is Node ) {
					if (entity==lastClick && (new Date().getTime()-lastClickTime.getTime())<1000) {
						if (selectedWay.length==1 && selectedWay.getNode(0).parentWays.length==1) {
							// double-click to create new POI
                            stopDrawing();
                            MainUndoStack.getGlobalStack().undo(); // undo the BeginWayAction that (presumably?) just happened
                            
                            var newPoiAction:CreatePOIAction = new CreatePOIAction(
								{},
								controller.map.coord2lat(event.localY),
								controller.map.coord2lon(event.localX));
                            MainUndoStack.getGlobalStack().addAction(newPoiAction);
                            return new SelectedPOINode(newPoiAction.getNode());
						} else {
							// double-click at end of way
							return stopDrawing();
						}
					} else {
						appendNode(entity as Node, MainUndoStack.getGlobalStack().addAction);
						if (focus is Way) {
                          controller.map.setHighlightOnNodes(focus as Way, { hoverway: false });
                        }
						controller.map.setHighlight(entity, { selectedway: true });
						resetElastic(entity as Node);
						lastClick=entity;
						if (selectedWay.getNode(0)==selectedWay.getNode(selectedWay.length-1)) {
							return new SelectedWay(selectedWay);
						}
					}
				} else if ( entity is Way ) {
					if (entity as Way==selectedWay) {
						// add junction node - self-intersecting way
			            var lat:Number = controller.map.coord2lat(event.localY);
			            var lon:Number = controller.map.coord2lon(event.localX);
			            var undo:CompositeUndoableAction = new CompositeUndoableAction("Insert node");
			            node = controller.connection.createNode({}, lat, lon, undo.push);
			            selectedWay.insertNodeAtClosestPosition(node, true, undo.push);
						appendNode(node,undo.push);
			            MainUndoStack.getGlobalStack().addAction(undo);
					} else {
                        // add junction node - another way
                        var jnct:CompositeUndoableAction = new CompositeUndoableAction("Junction Node");
                        node = createAndAddNode(event, jnct.push);
                        Way(entity).insertNodeAtClosestPosition(node, true, jnct.push);
                        MainUndoStack.getGlobalStack().addAction(jnct);
                        controller.map.setHighlight(node, { selectedway: true });
                        controller.map.setPurgable(node, false);
					}
					resetElastic(node);
					lastClick=node;
					controller.map.setHighlightOnNodes(entity as Way, { hoverway: false });
					controller.map.setHighlightOnNodes(selectedWay, { selectedway: true });
				}
				lastClickTime=new Date();
			} else if ( event.type == MouseEvent.MOUSE_MOVE && elastic ) {
				mouse = new Point(
						  controller.map.coord2lon(event.localX),
						  controller.map.coord2latp(event.localY));
				elastic.end = mouse;
			} else if ( event.type == MouseEvent.ROLL_OVER && !isBackground ) {
				if (focus is Way && focus!=selectedWay) {
					hoverEntity=focus;
					controller.map.setHighlightOnNodes(focus as Way, { hoverway: true });
				}
				if (entity is Node && focus is Way && Way(focus).endsWith(Node(entity))) {
					if (focus==selectedWay) { controller.setCursor(controller.pen_so); }
					                   else { controller.setCursor(controller.pen_o); }
				} else if (entity is Node) {
					controller.setCursor(controller.pen_x);
				} else {
					controller.setCursor(controller.pen_plus);
				}
			} else if ( event.type == MouseEvent.MOUSE_OUT && !isBackground ) {
				if (focus is Way && entity!=selectedWay) {
					hoverEntity=null;
					controller.map.setHighlightOnNodes(focus as Way, { hoverway: false });
					// ** We could do with an optional way of calling WayUI.redraw to only do the nodes, which would be a
					// useful optimisation.
				}
				controller.setCursor(controller.pen);
			}

			return this;
		}
		
		protected function resetElastic(node:Node):void {
			var mouse:Point = new Point(node.lon, node.latp);
			elastic.start = mouse;
			elastic.end = mouse;
		}

        /* Fix up the elastic after a WayNode event - e.g. triggered by undo */
        private function fixElastic(event:Event):void {
            if (selectedWay == null) return;
            var node:Node
            if (editEnd) {
              node = selectedWay.getNode(selectedWay.length-1);
            } else {
              node = selectedWay.getNode(0);
            }
            if (node) { //maybe selectedWay doesn't have any nodes left
              elastic.start = new Point(node.lon, node.latp);
            }
        }

		override public function processKeyboardEvent(event:KeyboardEvent):ControllerState {
			switch (event.keyCode) {
				case 13:					return keyExitDrawing();
				case 27:					return keyExitDrawing();
				case Keyboard.DELETE:		return backspaceNode(MainUndoStack.getGlobalStack().addAction);
				case Keyboard.BACKSPACE:	return backspaceNode(MainUndoStack.getGlobalStack().addAction);
				case 82:					repeatTags(selectedWay); return this;
			}
			var cs:ControllerState = sharedKeyboardEvents(event);
			return cs ? cs : this;
		}
		
		protected function keyExitDrawing():ControllerState {
			var cs:ControllerState=stopDrawing();
			if (selectedWay.length==1) { 
				if (MainUndoStack.getGlobalStack().undoIfAction(BeginWayAction)) { 
					return new NoSelection();
				}
				return deleteWay();
			}
			return cs;
		}
		
		protected function stopDrawing():ControllerState {
			if ( hoverEntity ) {
				controller.map.setHighlightOnNodes(hoverEntity as Way, { hoverway: false });
				hoverEntity = null;
			}

			if ( leaveNodeSelected ) {
			    return new SelectedWayNode(selectedWay, editEnd ? selectedWay.length - 1 : 0);
			} else {
			    return new SelectedWay(selectedWay);
			}
		}

		public function createAndAddNode(event:MouseEvent, performAction:Function):Node {
		    var undo:CompositeUndoableAction = new CompositeUndoableAction("Add node");
		    
			var lat:Number = controller.map.coord2lat(event.localY);
			var lon:Number = controller.map.coord2lon(event.localX);
			var node:Node = controller.connection.createNode({}, lat, lon, undo.push);
			appendNode(node, undo.push);
			
			performAction(undo);
			return node;
		}
		
		protected function appendNode(node:Node, performAction:Function):void {
			if ( editEnd )
				selectedWay.appendNode(node, performAction);
			else
				selectedWay.insertNode(0, node, performAction);
		}
		
		protected function backspaceNode(performAction:Function):ControllerState {
			var node:Node;
			var undo:CompositeUndoableAction = new CompositeUndoableAction("Remove node");
			var newDraw:int;
            var state:ControllerState;

			if (editEnd) {
				node=selectedWay.getNode(selectedWay.length-1);
				selectedWay.removeNodeByIndex(selectedWay.length-1, undo.push);
				newDraw=selectedWay.length-2;
			} else {
				node=selectedWay.getNode(0);
				selectedWay.removeNodeByIndex(0, undo.push);
				newDraw=0;
			}
			if (node.numParentWays==1 && selectedWay.hasOnceOnly(node)) {
				controller.map.setPurgable(node, true);
				controller.connection.unregisterPOI(node);
				node.remove(undo.push);
			}

			if (newDraw>=0 && newDraw<=selectedWay.length-2) {
				var mouse:Point = new Point(selectedWay.getNode(newDraw).lon, selectedWay.getNode(newDraw).latp);
				elastic.start = mouse;
				state = this;
			} else {
                selectedWay.remove(undo.push);
                state = new NoSelection();
			}

            performAction(undo);

            if(!node.isDeleted()) { // i.e. was junction with another way (or is now POI)
              controller.map.setHighlight(node, {selectedway: false});
            }
            return state;
		}
		
		override public function enterState():void {
			super.enterState();
			
			var node:Node = selectedWay.getNode(editEnd ? selectedWay.length - 1 : 0);
			var start:Point = new Point(node.lon, node.latp);
			elastic = new Elastic(controller.map, start, start);
			controller.setCursor(controller.pen);
			Globals.vars.root.addDebug("**** -> "+this);
		}
		override public function exitState(newState:ControllerState):void {
			super.exitState(newState);
			controller.setCursor(null);
			elastic.removeSprites();
			elastic = null;
			Globals.vars.root.addDebug("**** <- "+this);
		}
		override public function toString():String {
			return "DrawWay";
		}
	}
}
