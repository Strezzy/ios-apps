/* Original world and level data. Coordinates: X along the story, Y up, Z depth. */
(() => {
  'use strict';
  const platforms = [
    {id:'village',x:-150,y:-72,z:-92,w:870,h:72,d:184,kind:'earth'},
    {id:'far-bank',x:968,y:-84,z:-92,w:1080,h:84,d:184,kind:'earth'},
    {id:'hidden-bridge',x:695,y:-8,z:-79,w:300,h:8,d:35,kind:'bridge'},
    {id:'step-one',x:1160,y:0,z:-92,w:48,h:21,d:184,kind:'stone'},
    {id:'step-two',x:1208,y:0,z:-92,w:54,h:40,d:184,kind:'stone'},
    {id:'step-three',x:1262,y:0,z:-92,w:45,h:21,d:184,kind:'stone'},
    {id:'lookout',x:1390,y:0,z:46,w:78,h:24,d:36,kind:'stone'}
  ];
  const obstacles = [
    {id:'paper-wall',x:362,y:0,z:-1,w:24,h:126,d:2,kind:'paper'},
    {id:'paper-gate',x:1588,y:0,z:-1,w:20,h:118,d:2,kind:'gate'}
  ];
  const shards = [
    {x:212,y:20,z:0},{x:282,y:34,z:0},
    {x:380,y:17,z:48},{x:482,y:22,z:0},
    {x:628,y:29,z:0},{x:738,y:18,z:-62},
    {x:941,y:19,z:-62},{x:1070,y:27,z:0},
    {x:1232,y:65,z:0},{x:1426,y:47,z:62},
    {x:1500,y:25,z:0},{x:1730,y:30,z:0}
  ];
  const npcs = [
    {id:'orin',sprite:'sage',name:'Orin',x:151,y:0,z:0,depth:.6,
      lines:['The world has always had another side.','Touch the prism. Then step around what stops you.']},
    {id:'pip',sprite:'child',name:'Pip',x:613,y:0,z:0,depth:.6,
      lines:['Our gate has lost its light.','The spark is behind the broken road. Could you bring it home?']},
    {id:'keeper',sprite:'sage',name:'The Keeper',x:1480,y:0,z:0,depth:.6,
      lines:['You can see the space between things.','Bring the lost spark to this lantern. The gate will remember.']}
  ];
  window.TD_WORLD = Object.freeze({
    name:'The Folded Forest',chapter:1,width:2048,
    spawn:{x:72,y:0,z:0},
    platforms,obstacles,shards,npcs,
    prism:{x:240,y:20,z:0},
    spark:{x:845,y:18,z:-62},
    beacon:{x:1510,y:0,z:0},
    finish:{x:1830,y:0,z:0},
    checkpoints:[{x:492,y:0,z:0},{x:1040,y:0,z:0},{x:1645,y:0,z:0}],
    palette:{sky:'#10182e',fog:'#293b56',mint:'#81f2ce',gold:'#ffd58b',violet:'#9784ef',coral:'#f296a0'}
  });
})();
