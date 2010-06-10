package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.geom.*;
	import flash.ui.Keyboard;
	import net.systemeD.potlatch2.EditController;
	import net.systemeD.halcyon.connection.*;
	import net.systemeD.halcyon.Elastic;
	import net.systemeD.halcyon.Globals;

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
		}
		
		override public function processMouseEvent(event:MouseEvent, entity:Entity):ControllerState {
			var mouse:Point;
			var node:Node;
			if (entity == null && hoverEntity) { entity=hoverEntity; }
			var focus:Entity = getTopLevelFocusEntity(entity);

			if ( event.type == MouseEvent.MOUSE_UP ) {
				if ( entity == null ) {
					node = createAndAddNode(event);
					resetElastic(node);
					lastClick=node;
				} else if ( entity is Node ) {
					if (entity==lastClick && (new Date().getTime()-lastClickTime.getTime())<1000) {
						if (selectedWay.length==1 && selectedWay.getNode(0).parentWays.length==1) {
							// double-click to create new POI
							node=selectedWay.getNode(0);
							stopDrawing();
							node.setDeletedState(false);	// has just been deleted by stopDrawing
							controller.connection.registerPOI(node);
							return new SelectedPOINode(node);
						} else {
							// double-click at end of way
							return stopDrawing();
						}
					} else {
						appendNode(entity as Node, MainUndoStack.getGlobalStack().addAction);
						controller.map.setHighlight(focus, { showNodesHover: false });
						controller.map.setHighlight(selectedWay, { showNodes: true });
						resetElastic(entity as Node);
						lastClick=entity;
						if (selectedWay.getNode(0)==selectedWay.getNode(selectedWay.length-1)) {
							return new SelectedWay(selectedWay);
						}
					}
				} else if ( entity is Way ) {
					node = createAndAddNode(event);
					Way(entity).insertNodeAtClosestPosition(node, true,
					    MainUndoStack.getGlobalStack().addAction);
					resetElastic(node);
					lastClick=node;
					controller.map.setHighlight(entity, { showNodesHover: false });
					controller.map.setHighlight(selectedWay, { showNodes: true });
				}
				lastClickTime=new Date();
			} else if ( event.type == MouseEvent.MOUSE_MOVE ) {
				mouse = new Point(
						  controller.map.coord2lon(event.localX),
						  controller.map.coord2latp(event.localY));
				elastic.end = mouse;
			} else if ( event.type == MouseEvent.ROLL_OVER ) {
				if (focus!=selectedWay) {
					hoverEntity=focus;
					controller.map.setHighlight(focus, { showNodesHover: true });
				}
				if (entity is Node && Way(focus).endsWith(Node(entity))) {
					if (focus==selectedWay) { controller.setCursor(controller.pen_so); }
					                   else { controller.setCursor(controller.pen_o); }
				} else if (entity is Node) {
					controller.setCursor(controller.pen_x);
				} else {
					controller.setCursor(controller.pen_plus);
				}
			} else if ( event.type == MouseEvent.MOUSE_OUT ) {
				if (focus!=selectedWay) {
					hoverEntity=null;
					controller.map.setHighlight(focus, { showNodesHover: false });
					controller.map.setHighlight(selectedWay, { showNodes: true });
					// ** this call to setHighlight(selectedWay) is necessary in case the hovered way (blue nodes)
					// shares any nodes with the selected way (red nodes): if they do, they'll be wiped out by the
					// first call.
					// Ultimately we should fix this by referring to 'way :selected nodes' instead of 'nodes :selectedway'.
					// But this will do for now.
					// We could do with an optional way of calling WayUI.redraw to only do the nodes, which would be a
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

		override public function processKeyboardEvent(event:KeyboardEvent):ControllerState {
			switch (event.keyCode) {
				case 13:					return stopDrawing();
				case 27:					return stopDrawing();
				case Keyboard.BACKSPACE:	return backspaceNode(MainUndoStack.getGlobalStack().addAction);
				case 82:					repeatTags(selectedWay); return this;
			}
			var cs:ControllerState = sharedKeyboardEvents(event);
			return cs ? cs : this;
		}
		
		protected function stopDrawing():ControllerState {
			if ( selectedWay.length<2) {
				controller.map.setHighlight(selectedWay, { showNodes: false });
				selectedWay.remove(MainUndoStack.getGlobalStack().addAction);
				// delete controller.map.ways[selectedWay.id];
				return new NoSelection();
			} else if ( leaveNodeSelected ) {
			    return new SelectedWayNode(selectedWay, editEnd ? selectedWay.length - 1 : 0);
			} else {
			    return new SelectedWay(selectedWay);
			}
			return this;
		}

		public function createAndAddNode(event:MouseEvent):Node {
		    var undo:CompositeUndoableAction = new CompositeUndoableAction("Add node");
		    
			var lat:Number = controller.map.coord2lat(event.localY);
			var lon:Number = controller.map.coord2lon(event.localX);
			var node:Node = controller.connection.createNode({}, lat, lon, undo.push);
			appendNode(node, undo.push);
			
			MainUndoStack.getGlobalStack().addAction(undo);
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
			if (editEnd) {
				node=selectedWay.getNode(selectedWay.length-1);
				selectedWay.removeNodeByIndex(selectedWay.length-1, undo.push);
				newDraw=selectedWay.length-2;
			} else {
				node=selectedWay.getNode(0);
				selectedWay.removeNodeByIndex(0, undo.push);
				newDraw=0;
			}
			if (node.numParentWays==1) {
				controller.connection.unregisterPOI(node);
				node.remove(undo.push);
			}
			MainUndoStack.getGlobalStack().addAction(undo);

			if (newDraw>=0 && newDraw<=selectedWay.length-1) {
				var mouse:Point = new Point(selectedWay.getNode(newDraw).lon, selectedWay.getNode(newDraw).latp);
				elastic.start = mouse;
				return this;
			} else {
				return new NoSelection();
			}
		}
		
		override public function enterState():void {
			super.enterState();
			
			var node:Node = selectedWay.getNode(editEnd ? selectedWay.length - 1 : 0);
			var start:Point = new Point(node.lon, node.latp);
			elastic = new Elastic(controller.map, start, start);
			controller.setCursor(controller.pen);
			Globals.vars.root.addDebug("**** -> "+this);
		}
		override public function exitState():void {
			super.exitState();
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
