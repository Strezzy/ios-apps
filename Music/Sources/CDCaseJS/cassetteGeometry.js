// Cassette-specific geometry, built with the same optical rails and sheets as the CD.
import * as THREE from './vendor/three.module.js';
import { RodBuilder, roundedRect, circle, sheet, mergeSheets } from './caseGeometry.js';
const rail = (hw, hh, zc) => ({hw,hh,rc:Math.min(hw,hh)*.94,zc,seg:5});
export function cassetteTrayGeometry() {
  const rods=new RodBuilder();
  rods.add(roundedRect(0,0,70,47,5),rail(3,3,-.7),true);
  rods.add(roundedRect(0,0,72,49,6),rail(.7,.7,-4.5),true);
  rods.add(roundedRect(0,0,66,42,4),rail(1.1,1.8,-1.8),true);
  for(const x of [-49,49]) rods.add([[x-8,-49],[x+8,-49]],rail(2.1,2.1,4));
  for(const x of [-30,30]) rods.add(circle(x,0,7),rail(.8,2,-2),true);
  return {rods:rods.build(),sheets:sheet(roundedRect(0,0,73,50,6),-5.2,-3.8)};
}
export function cassetteLidGeometry() {
  const rods=new RodBuilder();
  rods.add(roundedRect(0,0,72,49,5),rail(1,1,4),true);
  rods.add(roundedRect(0,0,69,46,4),rail(.45,.45,3.2),true);
  for(const x of [-25,25]) rods.add([[x-7,-49],[x+7,-49]],rail(2,2,4));
  // Locking tabs and injection-moulded ribs.
  for(const x of [-32,32]) rods.add([[x-4,49],[x+4,49]],rail(.7,.7,3.4));
  return {rods:rods.build(),sheets:sheet(roundedRect(0,0,73,50,6),3,5)};
}
export function cassetteBodyGeometry() {
  const holes=[-30,30].map(x=>circle(x,1,18,1.3).reverse());
  const g=sheet(roundedRect(0,0,64,39,5),-2.8,-1.1,holes);
  g.setAttribute('aFace',new THREE.Float32BufferAttribute(new Array(g.attributes.position.count).fill(0),1));
  return g;
}
export function cassetteShellGeometry() {
  const rods=new RodBuilder();
  rods.add(roundedRect(0,0,64,39,5),rail(1.2,1.5,-1.7),true);
  rods.add(roundedRect(0,0,61,36,4),rail(.45,.6,-.7),true);
  for(const x of [-30,30]) rods.add(circle(x,1,18.2,1.3),rail(.7,.8,-.7),true);
  // Screw bosses, tape path and head opening make the silhouette read as tape.
  for(const x of [-57,57]) for(const y of [-31,31]) rods.add(circle(x,y,2.2,.8),rail(.55,.6,-.5),true);
  rods.add([[-43,-33],[-36,-23],[36,-23],[43,-33]],rail(1,1,-.7));
  rods.add([[-35,-33],[35,-33]],rail(.65,.8,-.6));
  return {rods:rods.build(),sheets:mergeSheets([-30,30].map(x=>sheet(circle(x,1,18,1.3),-.5,-.1)))};
}
export function cassetteReelGeometry() {
  const parts=[sheet(circle(0,0,16.9,1),-2.4,-1.6,[circle(0,0,5,1).reverse()])];
  // Six actual hub teeth rotate with each reel; the centre remains hollow.
  for(let i=0;i<6;i++) {
    const a=i*Math.PI/3,c=Math.cos(a),s=Math.sin(a);
    parts.push(sheet([[5,-1.5],[10,-2],[10,2],[5,1.5]].map(([x,y])=>[x*c-y*s,x*s+y*c]),-1.6,-.5));
  }
  const g=mergeSheets(parts);
  g.setAttribute('aFace',new THREE.Float32BufferAttribute(new Array(g.attributes.position.count).fill(0),1));
  return g;
}
export const CASSETTE_FRAG=`
 uniform sampler2D uArt; uniform sampler2D uArtPrevious; uniform float uArtMix;
 varying vec3 vLocal; varying vec3 vN; varying vec3 vP;
 void main(){
   vec2 uv=vLocal.xy/vec2(120.,76.)+.5;
   vec3 art=mix(texture2D(uArtPrevious,uv).rgb,texture2D(uArt,uv).rgb,uArtMix);
   float label=step(-24.,vLocal.y)*step(abs(vLocal.x),59.)*step(vLocal.y,34.);
   vec3 base=mix(vec3(.085,.095,.11),art,label);
   float light=.78+.22*abs(normalize(vN).z);
   float gloss=pow(max(0.,dot(reflect(normalize(vP),normalize(vN)),normalize(vec3(-.3,.5,1.)))),28.);
   gl_FragColor=vec4(base*light+vec3(.17)*gloss,1.);
 }`;
export const REEL_FRAG=`
 varying vec3 vLocal; varying vec3 vN; varying vec3 vP;
 void main(){
   float r=length(vLocal.xy),angle=atan(vLocal.y,vLocal.x);
   float tape=step(11.,r),grooves=.5+.5*sin(r*18.);
   vec3 base=mix(vec3(.79,.82,.85),vec3(.095,.065,.045)+grooves*.025,tape);
   float edge=pow(1.-abs(normalize(vN).z),2.);
   float spoke=step(.55,cos(angle*6.))*step(r,10.);
   gl_FragColor=vec4(base*(.82+.18*cos(angle)) + edge*.25+spoke*.1,1.);
 }`;
