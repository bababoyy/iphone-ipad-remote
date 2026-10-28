(function(){
'use strict';
var handler=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vcremote;
if(!handler)return;
var current=null;
function post(msg){handler.postMessage(msg)}
function Socket(url){
 this.url=String(url);this.readyState=0;current=this;
 var found=/[?&]pin=([0-9]{6})(?:&|$)/.exec(this.url);
 post({type:'connect',pin:found?found[1]:''});
}
Socket.CONNECTING=0;Socket.OPEN=1;Socket.CLOSED=3;
Socket.prototype.send=function(payload){
 if(this.readyState===1)post({type:'packet',payload:String(payload)});
};
Socket.prototype.close=function(){
 if(this.readyState===3)return;
 this.readyState=3;if(current===this)current=null;
 post({type:'disconnect'});
 if(typeof this.onclose==='function')this.onclose({code:1000});
};
window.WebSocket=Socket;
window.vcBLEEvent=function(type,message){
 var sock=current;if(!sock)return;
 if(type==='ready'){
   sock.readyState=1;if(typeof sock.onopen==='function')sock.onopen();
   var el=document.getElementById('status');if(el)el.textContent=message||'Bluetooth connected';
 }else{
   sock.readyState=3;current=null;
   if(type==='failure'&&typeof sock.onerror==='function')sock.onerror({message:message});
   if(typeof sock.onclose==='function')sock.onclose({code:1006});
   var e=document.getElementById('error');if(e&&message)e.textContent=message;
 }
};
document.addEventListener('DOMContentLoaded',function(){
 var select=document.getElementById('inputMode');
 if(select)Array.from(select.options).forEach(function(opt){if(opt.value!=='gamepad')opt.remove()});
});
})();