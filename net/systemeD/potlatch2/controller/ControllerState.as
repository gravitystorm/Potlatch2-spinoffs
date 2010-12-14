package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.display.*;
    import net.systemeD.halcyon.Map;
    import net.systemeD.halcyon.MapPaint;
    import net.systemeD.halcyon.connection.*;
    import net.systemeD.potlatch2.collections.Imagery;
    import net.systemeD.potlatch2.EditController;
	import net.systemeD.halcyon.Globals;
	import net.systemeD.potlatch2.save.SaveManager;
    public class ControllerState {

        protected var controller:EditController;
        protected var previousState:ControllerState;

		protected var _selection:Array=[];

        public function ControllerState() {}

        public function setController(controller:EditController):void {
            this.controller = controller;
        }

        public function setPreviousState(previousState:ControllerState):void {
            if ( this.previousState == null )
                this.previousState = previousState;
        }

		public function isSelectionState():Boolean {
			return true;
		}

        public function processMouseEvent(event:MouseEvent, entity:Entity):ControllerState {
            return this;
        }

        public function processKeyboardEvent(event:KeyboardEvent):ControllerState {
            return this;
        }

		public function get map():Map {
			return controller.map;
		}

        public function enterState():void {}
        public function exitState(newState:ControllerState):void {}

		public function toString():String {
			return "(No state)";
		}

		protected function sharedKeyboardEvents(event:KeyboardEvent):ControllerState {
			switch (event.keyCode) {
				case 66:	setSourceTag(); break;													// B - set source tag for current object
				case 67:	controller.connection.closeChangeset(); break;							// C - close changeset
				case 68:	controller.map.paint.alpha=1.3-controller.map.paint.alpha; return null;	// D - dim
				case 83:	SaveManager.saveChanges(); break;										// S - save
				case 84:	controller.tagViewer.togglePanel(); return null;						// T - toggle tags panel
				case 90:	MainUndoStack.getGlobalStack().undo(); return null;						// Z - undo
				case 187:	controller.tagViewer.addNewTag(); return null;							// + - add tag
				case 107:       controller.tagViewer.addNewTag(); return null;							// numpad + - add tag
			}
			return null;
		}

		protected function sharedMouseEvents(event:MouseEvent, entity:Entity):ControllerState {
			var paint:MapPaint = getMapPaint(DisplayObject(event.target));
            var focus:Entity = getTopLevelFocusEntity(entity);

			if ( paint && paint.isBackground ) {
				if ( event.type == MouseEvent.MOUSE_DOWN && ((event.shiftKey && event.ctrlKey) || event.altKey) ) {
					// alt-click to pull data out of vector background layer
					var newEntity:Entity=paint.findSource().pullThrough(entity,controller.connection);
					if (entity is Way) { return new SelectedWay(newEntity as Way); }
					else if (entity is Node) { return new SelectedPOINode(newEntity as Node); }
                } else if (event.type == MouseEvent.MOUSE_DOWN && entity is Marker) {
                    return new SelectedMarker(entity as Marker, paint.findSource());
				} else if ( event.type == MouseEvent.MOUSE_UP ) {
					return (this is NoSelection) ? null : new NoSelection();
				} else { return null; }
			}

			if ( event.type == MouseEvent.MOUSE_DOWN ) {
				if ( entity is Way ) {
					// click way
					return new DragWay(focus as Way, event);
				} else if ( focus is Node ) {
					// select POI node
					return new DragPOINode(entity as Node,event,false);
				} else if ( entity is Node && selectedWay && entity.hasParent(selectedWay) ) {
					// select node within this way
                	return new DragWayNode(selectedWay,  getNodeIndex(selectedWay,entity as Node),  event, false);
				} else if ( entity is Node && focus is Way ) {
					// select way node
					return new DragWayNode(focus as Way, getNodeIndex(focus as Way,entity as Node), event, false);
				} else if ( controller.keyDown(32) ) {
					// drag map
					return new DragBackground(event);
				}
            } else if ( event.type == MouseEvent.CLICK && focus == null && map.dragstate!=map.DRAGGING && this is SelectedMarker) {
                // this is identical to the below, but needed for unselecting markers on vector background layers.
                // Deselecting a POI or way on the main layer emits both CLICK and MOUSE_UP, but markers only CLICK
                // I'll leave it to someone who understands to decide whether they are the same thing and should be
                // combined with a (CLICK || MOUSE_UP)
                
                // "&& this is SelectedMarker" added by Steve Bennett. The CLICK event being processed for SelectedWay state
                // causes way to get unselected...so restrict the double processing as much as possible.  
                
                return (this is NoSelection) ? null : new NoSelection();
			} else if ( event.type == MouseEvent.MOUSE_UP && focus == null && map.dragstate!=map.DRAGGING) {
				return (this is NoSelection) ? null : new NoSelection();
			} else if ( event.type == MouseEvent.MOUSE_UP && focus && map.dragstate!=map.NOT_DRAGGING) {
				map.mouseUpHandler();	// in case the end-drag is over an EntityUI
			} else if ( event.type == MouseEvent.ROLL_OVER ) {
				controller.map.setHighlight(focus, { hover: true });
			} else if ( event.type == MouseEvent.MOUSE_OUT ) {
				controller.map.setHighlight(focus, { hover: false });
            } else if ( event.type == MouseEvent.MOUSE_WHEEL ) {
                if (event.delta > 0) {
                  map.zoomIn();
                } else if (event.delta < 0) {
                  map.zoomOut();
                }
            }
			return null;
		}

		public static function getTopLevelFocusEntity(entity:Entity):Entity {
			if ( entity is Node ) {
				for each (var parent:Entity in entity.parentWays) {
					return parent;
				}
				return entity;
			} else if ( entity is Way ) {
				return entity;
			} else {
				return null;
			}
		}

		protected function getMapPaint(d:DisplayObject):MapPaint {
			while (d) {
				if (d is MapPaint) { return MapPaint(d); }
				d=d.parent;
			}
			return null;
		}

		protected function getNodeIndex(way:Way,node:Node):uint {
			for (var i:uint=0; i<way.length; i++) {
				if (way.getNode(i)==node) { return i; }
			}
			return null;
		}

		protected function repeatTags(object:Entity):void {
			if (!controller.clipboards[object.getType()]) { return; }
			object.suspend();

		    var undo:CompositeUndoableAction = new CompositeUndoableAction("Repeat tags");
			for (var k:String in controller.clipboards[object.getType()]) {
				object.setTag(k, controller.clipboards[object.getType()][k], undo.push)
			}
			MainUndoStack.getGlobalStack().addAction(undo);
                        controller.updateSelectionUI();
			object.resume();


		}

		protected function setSourceTag():void {
			if (selectCount!=1) { return; }
			if (Imagery.instance().selected && Imagery.instance().selected.sourcetag) {
				firstSelected.setTag('source',Imagery.instance().selected.sourcetag, MainUndoStack.getGlobalStack().addAction);
			}
			controller.updateSelectionUI();
		}

		// Selection getters

		public function get selectCount():uint {
			return _selection.length;
		}

		public function get selection():Array {
			return _selection;
		}

		public function get firstSelected():Entity {
			if (_selection.length==0) { return null; }
			return _selection[0];
		}

		public function get selectedWay():Way {
			if (firstSelected is Way) { return firstSelected as Way; }
			return null;
		}

		public function get selectedWays():Array {
			var selectedWays:Array=[];
			for each (var item:Entity in _selection) {
				if (item is Way) { selectedWays.push(item); }
			}
			return selectedWays;
		}

		public function hasSelectedWays():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way) { return true; }
			}
			return false;
		}

		public function hasSelectedAreas():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way && Way(item).isArea()) { return true; }
			}
			return false;
		}

		public function hasSelectedUnclosedWays():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way && !Way(item).isArea()) { return true; }
			}
			return false;
		}

		public function hasAdjoiningWays():Boolean {
			if (_selection.length<2) { return false; }
			var endNodes:Object={};
			for each (var item:Entity in _selection) {
				if (item is Way && !Way(item).isArea()) {
					if (endNodes[Way(item).getNode(0).id]) return true;
					if (endNodes[Way(item).getLastNode().id]) return true;
					endNodes[Way(item).getNode(0).id]=true;
					endNodes[Way(item).getLastNode().id]=true;
				}
			}
			return false;
		}

		// Selection setters

		public function set selection(items:Array):void {
			_selection=items;
		}

		public function addToSelection(items:Array):void {
			for each (var item:Entity in items) {
				if (_selection.indexOf(item)==-1) { _selection.push(item); }
			}
		}

		public function removeFromSelection(items:Array):void {
			for each (var item:Entity in items) {
				if (_selection.indexOf(item)>-1) {
					_selection.splice(_selection.indexOf(item),1);
				}
			}
		}

		public function toggleSelection(item:Entity):Boolean {
			if (_selection.indexOf(item)==-1) {
				_selection.push(item); return true;
			}
			_selection.splice(_selection.indexOf(item),1); return false;
		}
    }
}
