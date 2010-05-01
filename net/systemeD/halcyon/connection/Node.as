package net.systemeD.halcyon.connection {

    import net.systemeD.halcyon.connection.actions.*;

    public class Node extends Entity {
        private var _lat:Number;
        private var _latproj:Number;
        private var _lon:Number;

        public function Node(id:Number, version:uint, tags:Object, loaded:Boolean, lat:Number, lon:Number) {
            super(id, version, tags, loaded);
            this._lat = lat;
            this._latproj = lat2latp(lat);
            this._lon = lon;
        }

		public function update(version:uint, tags:Object, loaded:Boolean, lat:Number, lon:Number):void {
			updateEntityProperties(version,tags,loaded); this.lat=lat; this.lon=lon;
		}

        public function get lat():Number {
            return _lat;
        }

        public function get latp():Number {
            return _latproj;
        }

        public function get lon():Number {
            return _lon;
        }

        private function setLatLonImmediate(lat:Number, lon:Number):void {
            this._lat = lat;
            this._latproj = lat2latp(lat);
            this._lon = lon;
        }
        
        public function set lat(lat:Number):void {
            MainUndoStack.getGlobalStack().addAction(new MoveNodeAction(this, lat, _lon, setLatLonImmediate));
        }

        public function set latp(latproj:Number):void {
            MainUndoStack.getGlobalStack().addAction(new MoveNodeAction(this, latp2lat(latproj), _lon, setLatLonImmediate));
        }

        public function set lon(lon:Number):void {
            MainUndoStack.getGlobalStack().addAction(new MoveNodeAction(this, _lat, lon, setLatLonImmediate));
        }
        
        public function setLatLon(lat:Number, lon:Number):void {
            MainUndoStack.getGlobalStack().addAction(new MoveNodeAction(this, lat, lon, setLatLonImmediate));
        } 

		public function setLonLatp(lon:Number,latproj:Number, performAction:Function):void {
		    performAction(new MoveNodeAction(this, latp2lat(latproj), lon, setLatLonImmediate));
		}

        public override function toString():String {
            return "Node("+id+"@"+version+"): "+lat+","+lon+" "+getTagList();
        }

		public override function remove(performAction:Function):void {
			performAction(new DeleteNodeAction(this, setDeletedState));
		}
		
		internal override function isEmpty():Boolean {
			return deleted;
		}

        public static function lat2latp(lat:Number):Number {
            return 180/Math.PI * Math.log(Math.tan(Math.PI/4+lat*(Math.PI/180)/2));
        }

		public static function latp2lat(a:Number):Number {
		    return 180/Math.PI * (2 * Math.atan(Math.exp(a*Math.PI/180)) - Math.PI/2);
		}
		
		public override function getType():String {
			return 'node';
		}
    }

}
