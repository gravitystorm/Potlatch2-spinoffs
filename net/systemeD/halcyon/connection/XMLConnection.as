package net.systemeD.halcyon.connection {

    import flash.events.*;

	import flash.system.Security;
	import flash.net.*;
    import org.iotashan.oauth.*;

	import net.systemeD.halcyon.MapEvent;

	public class XMLConnection extends XMLBaseConnection {

        //public var readConnection:NetConnection;

		public function XMLConnection() {

			if (Connection.policyURL!='')
                Security.loadPolicyFile(Connection.policyURL);
            var oauthPolicy:String = Connection.getParam("oauth_policy", "");
            if ( oauthPolicy != "" ) {
                Security.loadPolicyFile(oauthPolicy);
            }
		}
		
		override public function loadBbox(left:Number,right:Number,
								top:Number,bottom:Number):void {
            var mapVars:URLVariables = new URLVariables();
            mapVars.bbox= left+","+bottom+","+right+","+top;

            var mapRequest:URLRequest = new URLRequest(Connection.apiBaseURL+"map");
            mapRequest.data = mapVars;

            var mapLoader:URLLoader = new URLLoader();
            mapLoader.addEventListener(Event.COMPLETE, loadedMap);
            mapLoader.addEventListener(IOErrorEvent.IO_ERROR, errorOnMapLoad);
            mapLoader.addEventListener(HTTPStatusEvent.HTTP_STATUS, mapLoadStatus);
            mapLoader.load(mapRequest);
            dispatchEvent(new Event(LOAD_STARTED));
		}

        private function errorOnMapLoad(event:Event):void {
			dispatchEvent(new MapEvent(MapEvent.ERROR, { message: "Couldn't load the map" } ));
        }
        private function mapLoadStatus(event:HTTPStatusEvent):void {
            trace("loading map status = "+event.status);
        }

        protected var appID:OAuthConsumer;
        protected var authToken:OAuthToken;
        
	    override public function setAppID(id:Object):void {
	        appID = OAuthConsumer(id);
	    }
	    
	    override public function setAuthToken(id:Object):void {
	        authToken = OAuthToken(id);
	    }

        private var httpStatus:int = 0;
        
        private function recordStatus(event:HTTPStatusEvent):void {
            httpStatus = event.status;
        }
        
        private var lastUploadedChangesetTags:Object;
        
        override public function createChangeset(tags:Object):void {
            lastUploadedChangesetTags = tags;
            
   	        var changesetXML:XML = <osm version="0.6"><changeset /></osm>;
	        var changeset:XML = <changeset />;
	        for (var tagKey:Object in tags) {
              var tagXML:XML = <tag/>;
              tagXML.@k = tagKey;
              tagXML.@v = tags[tagKey];
              changesetXML.changeset.appendChild(tagXML);
            }        

            // make an OAuth query
            var sig:IOAuthSignatureMethod = new OAuthSignatureMethod_HMAC_SHA1();
            var url:String = Connection.apiBaseURL+"changeset/create";
            //var params:Object = { _method: "PUT" };
            var oauthRequest:OAuthRequest = new OAuthRequest("PUT", url, null, appID, authToken);
            var urlStr:Object = oauthRequest.buildRequest(sig, OAuthRequest.RESULT_TYPE_URL_STRING)

            // build the actual request
            var urlReq:URLRequest = new URLRequest(String(urlStr));
            urlReq.method = "POST";
            urlReq.data = changesetXML.toXMLString();
            urlReq.contentType = "application/xml";
            urlReq.requestHeaders = new Array(new URLRequestHeader("X_HTTP_METHOD_OVERRIDE", "PUT"));
            var loader:URLLoader = new URLLoader();
            loader.addEventListener(Event.COMPLETE, changesetCreateComplete);
            loader.addEventListener(IOErrorEvent.IO_ERROR, changesetCreateError);
            loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, recordStatus);
	        loader.load(urlReq);
	    }

        private function changesetCreateComplete(event:Event):void {
            // response should be a Number changeset id
            var id:Number = Number(URLLoader(event.target).data);
            
            // which means we now have a new changeset!
            setActiveChangeset(new Changeset(id, lastUploadedChangesetTags));
        }

        private function changesetCreateError(event:IOErrorEvent):void {
            dispatchEvent(new Event(NEW_CHANGESET_ERROR));
        }
        
        override public function uploadChanges():void {
            var changeset:Changeset = getActiveChangeset();
            var upload:XML = <osmChange version="0.6"/>
            upload.appendChild(addCreated(changeset, getAllNodeIDs, getNode, serialiseNode));
            upload.appendChild(addCreated(changeset, getAllWayIDs, getWay, serialiseWay));
            upload.appendChild(addCreated(changeset, getAllRelationIDs, getRelation, serialiseRelation));
            upload.appendChild(addModified(changeset, getAllNodeIDs, getNode, serialiseNode));
            upload.appendChild(addModified(changeset, getAllWayIDs, getWay, serialiseWay));
            upload.appendChild(addModified(changeset, getAllRelationIDs, getRelation, serialiseRelation));
            upload.appendChild(addDeleted(changeset, getAllRelationIDs, getRelation, serialiseEntityRoot));
            upload.appendChild(addDeleted(changeset, getAllWayIDs, getWay, serialiseEntityRoot));
            upload.appendChild(addDeleted(changeset, getAllNodeIDs, getNode, serialiseEntityRoot));

            // now actually upload them
            // make an OAuth query
            var sig:IOAuthSignatureMethod = new OAuthSignatureMethod_HMAC_SHA1();
            var url:String = Connection.apiBaseURL+"changeset/" + changeset.id + "/upload";
            var oauthRequest:OAuthRequest = new OAuthRequest("POST", url, null, appID, authToken);
            var urlStr:Object = oauthRequest.buildRequest(sig, OAuthRequest.RESULT_TYPE_URL_STRING)

            // build the actual request
            var urlReq:URLRequest = new URLRequest(String(urlStr));
            urlReq.method = "POST";
            urlReq.data = upload.toXMLString();
            urlReq.contentType = "text/xml";
            var loader:URLLoader = new URLLoader();
            loader.addEventListener(Event.COMPLETE, diffUploadComplete);
            loader.addEventListener(IOErrorEvent.IO_ERROR, diffUploadError);
            loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, recordStatus);
	        loader.load(urlReq);
	        
	        dispatchEvent(new Event(SAVE_STARTED));
        }

        private function diffUploadComplete(event:Event):void {
            // response should be XML describing the progress
            var results:XML = new XML((URLLoader(event.target).data));
            
            for each( var update:XML in results.child("*") ) {
                var oldID:Number = Number(update.@old_id);
                var newID:Number = Number(update.@new_id);
                var version:uint = uint(update.@new_version);
                var type:String = update.name();

				if (newID==0) {
					// delete
	                if ( type == "node" ) killNode(oldID);
	                else if ( type == "way" ) killWay(oldID);
	                else if ( type == "relation" ) killRelation(oldID);
					
				} else {
					// create/update
	                var entity:Entity;
	                if ( type == "node" ) entity = getNode(oldID);
	                else if ( type == "way" ) entity = getWay(oldID);
	                else if ( type == "relation" ) entity = getRelation(oldID);
	                entity.markClean(newID, version);
                
	                if ( oldID != newID ) {
	                    if ( type == "node" ) renumberNode(oldID, entity as Node, false);
	                    else if ( type == "way" ) renumberWay(oldID, entity as Way, false);
	                    else if ( type == "relation" ) renumberRelation(oldID, entity as Relation, false);
	                }
				}
            }

            dispatchEvent(new SaveCompleteEvent(SAVE_COMPLETED, true));
			freshenActiveChangeset();
            markClean(); // marks the connection clean. Pressing undo from this point on leads to unexpected results
            MainUndoStack.getGlobalStack().breakUndo(); // so, for now, break the undo stack
        }

        private function diffUploadError(event:IOErrorEvent):void {
			dispatchEvent(new MapEvent(MapEvent.ERROR, { message: "Couldn't upload data: "+httpStatus+" "+event.text } ));
	        dispatchEvent(new SaveCompleteEvent(SAVE_COMPLETED, false));
        }

        private function addCreated(changeset:Changeset, getIDs:Function, get:Function, serialise:Function):XML {
            var create:XML = <create version="0.6"/>
            for each( var id:Number in getIDs() ) {
                var entity:Entity = get(id);
                if ( id >= 0 || entity.deleted )
                    continue;
                    
                var xml:XML = serialise(entity);
                xml.@changeset = changeset.id;
                create.appendChild(xml);
            }
            return create.hasComplexContent() ? create : <!-- blank create section -->;
        }

		private function addDeleted(changeset:Changeset, getIDs:Function, get:Function, serialise:Function):XML {
            var del:XML = <delete version="0.6"/>
            for each( var id:Number in getIDs() ) {
                var entity:Entity = get(id);
                // creates are already included
                if ( id < 0 || !entity.deleted )
                    continue;
                    
                var xml:XML = serialise(entity);
                xml.@changeset = changeset.id;
                del.appendChild(xml);
            }
            return del.hasComplexContent() ? del : <!-- blank delete section -->;
		}

        private function addModified(changeset:Changeset, getIDs:Function, get:Function, serialise:Function):XML {
            var modify:XML = <modify version="0.6"/>
            for each( var id:Number in getIDs() ) {
                var entity:Entity = get(id);
                // creates and deletes are already included
                if ( id < 0 || entity.deleted || !entity.isDirty )
                    continue;
                    
                var xml:XML = serialise(entity);
                xml.@changeset = changeset.id;
                modify.appendChild(xml);
            }
            return modify.hasComplexContent() ? modify : <!-- blank modify section -->;
        }

        private function serialiseNode(node:Node):XML {
            var xml:XML = serialiseEntityRoot(node); //<node/>
            serialiseEntityTags(node, xml);
            xml.@lat = node.lat;
            xml.@lon = node.lon;
            return xml;
        }

        private function serialiseWay(way:Way):XML {
            var xml:XML = serialiseEntityRoot(way); //<node/>
            serialiseEntityTags(way, xml);
            for ( var i:uint = 0; i < way.length; i++ ) {
                var nd:XML = <nd/>
                nd.@ref = way.getNode(i).id;
                xml.appendChild(nd);
            }
            return xml;
        }

        private function serialiseRelation(relation:Relation):XML {
            var xml:XML = serialiseEntityRoot(relation); //<node/>
            serialiseEntityTags(relation, xml);
            for ( var i:uint = 0; i < relation.length; i++ ) {
                var relMember:RelationMember = relation.getMember(i);
                var member:XML = <member/>
                member.@ref = relMember.entity.id;
                member.@type = relMember.entity.getType();
                member.@role = relMember.role;
                xml.appendChild(member);
            }
            return xml;
        }
        
		private function serialiseEntityRoot(entity:Object):XML {
			var xml:XML;
			if      (entity is Way     ) { xml = <way/> }
			else if (entity is Node    ) { xml = <node/> }
			else if (entity is Relation) { xml = <relation/> }
			xml.@id = entity.id;
			xml.@version = entity.version;
			return xml;
		}

        private function serialiseEntityTags(entity:Entity, xml:XML):void {
            xml.@id = entity.id;
            xml.@version = entity.version;
            for each( var tag:Tag in entity.getTagArray() ) {
              var tagXML:XML = <tag/>
              tagXML.@k = tag.key;
              tagXML.@v = tag.value;
              xml.appendChild(tagXML);
            }
        }

	}
}
