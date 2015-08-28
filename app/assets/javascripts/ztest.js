$(document).on('page:change', function(){
    var scene, camera, renderer;
    var geometry, material, mesh, width, length;

    init();
    animate();

    function init() {

        scene = new THREE.Scene();
        
        width = 250;
        height = 250;

        camera = new THREE.PerspectiveCamera( 75, width / height, 1, 10000 );
        camera.position.z = 900;

        geometry = new THREE.SphereGeometry( 500, 5, 2 );
        material = new THREE.MeshBasicMaterial( { color: 0x5f9ea0, wireframe: true } );

        mesh = new THREE.Mesh( geometry, material );
        scene.add( mesh );

        renderer = new THREE.WebGLRenderer({ alpha: true });
        renderer.setSize( width, height );

        $("div.penta").append(renderer.domElement);	
        // document.body.appendChild( renderer.domElement );

    }

    function animate() {

        requestAnimationFrame( animate );

        mesh.rotation.x += 0.02;
        mesh.rotation.y += 0.02;

        renderer.render( scene, camera );

    }
});
// 			// var scene = new THREE.Scene();
// // 			// var camera = new THREE.PerspectiveCamera( 75, window.innerWidth/window.innerHeight, 0.1, 1000 );

// // 			// var renderer = new THREE.WebGLRenderer();
// // 			// renderer.setSize( window.innerWidth, window.innerHeight );
// // 			// document.body.appendChild( renderer.domElement );

// // 			// var geometry = new THREE.BoxGeometry( 1, 1, 1 );
// // 			// var material = new THREE.MeshBasicMaterial( { color: 0x00ff00 } );
// // 			// var cube = new THREE.Mesh( geometry, material );
// // 			// scene.add( cube );

// // 			// camera.position.z = 5;

// // 			// var render = function () {
// // 			// 	requestAnimationFrame( render );

// // 			// 	cube.rotation.x += 0.1;
// // 			// 	cube.rotation.y += 0.1;

// // 			// 	renderer.render(scene, camera);
// // 			// };

// // 			// render();

// // 		// if ( ! Detector.webgl ) Detector.addGetWebGLMessage();

// // 			var container, stats;

// // 			var camera, cameraTarget, scene, renderer;

// // 			init();
// // 			animate();

// // 			function init() {

// // 				container = document.createElement( 'div' );
// // 				document.body.appendChild( container );

// // 				camera = new THREE.PerspectiveCamera( 35, window.innerWidth / window.innerHeight, 1, 15 );
// // 				camera.position.set( 3, 0.15, 3 );

// // 				cameraTarget = new THREE.Vector3( 0, -0.25, 0 );

// // 				scene = new THREE.Scene();
// // 				scene.fog = new THREE.Fog( 0x72645b, 2, 15 );


// // 				// Ground

// // 				var plane = new THREE.Mesh(
// // 					new THREE.PlaneBufferGeometry( 40, 40 ),
// // 					new THREE.MeshPhongMaterial( { color: 0x999999, specular: 0x101010 } )
// // 				);
// // 				plane.rotation.x = -Math.PI/2;
// // 				plane.position.y = -0.5;
// // 				scene.add( plane );

// // 				plane.receiveShadow = true;


// // 				// ASCII file

// // 				var loader = new THREE.STLLoader();
// // 				// loader.load( './models/stl/ascii/slotted_disk.stl', function ( geometry ) {
// // 				loader.load( './assets/tank_cap.stl', function ( geometry ) {

// // 					var material = new THREE.MeshPhongMaterial( { color: 0xff5533, specular: 0x111111, shininess: 200 } );
// // 					var mesh = new THREE.Mesh( geometry, material );

// // 					mesh.position.set( 0, - 0.25, 0.6 );
// // 					mesh.rotation.set( 0, - Math.PI / 2, 0 );
// // 					mesh.scale.set( 0.5, 0.5, 0.5 );

// // 					mesh.castShadow = true;
// // 					mesh.receiveShadow = true;

// // 					scene.add( mesh );

// // 				} );


// // 				// Binary files

// // 				var material = new THREE.MeshPhongMaterial( { color: 0xAAAAAA, specular: 0x111111, shininess: 200 } );

// // 				// loader.load( './models/stl/binary/pr2_head_pan.stl', function ( geometry ) {
// // 				loader.load( './assets/tank_cap.stl', function ( geometry ) {

// // 					var mesh = new THREE.Mesh( geometry, material );

// // 					mesh.position.set( 0, - 0.37, - 0.6 );
// // 					mesh.rotation.set( - Math.PI / 2, 0, 0 );
// // 					mesh.scale.set( 2, 2, 2 );

// // 					mesh.castShadow = true;
// // 					mesh.receiveShadow = true;

// // 					scene.add( mesh );

// // 				} );

// // 				// loader.load( './models/stl/binary/pr2_head_tilt.stl', function ( geometry ) {

// // 				// 	var mesh = new THREE.Mesh( geometry, material );

// // 				// 	mesh.position.set( 0.136, - 0.37, - 0.6 );
// // 				// 	mesh.rotation.set( - Math.PI / 2, 0.3, 0 );
// // 				// 	mesh.scale.set( 2, 2, 2 );

// // 				// 	mesh.castShadow = true;
// // 				// 	mesh.receiveShadow = true;

// // 				// 	scene.add( mesh );

// // 				// } );

// // 				// // Colored binary STL
// // 				// loader.load( './models/stl/binary/colored.stl', function ( geometry ) {

// // 				// 	var meshMaterial = material;
// // 				// 	if (geometry.hasColors) {
// // 				// 		meshMaterial = new THREE.MeshPhongMaterial({ opacity: geometry.alpha, vertexColors: THREE.VertexColors });
// // 				// 	}

// // 				// 	var mesh = new THREE.Mesh( geometry, meshMaterial );

// // 				// 	mesh.position.set( 0.5, 0.2, 0 );
// // 				// 	mesh.rotation.set( - Math.PI / 2, Math.PI / 2, 0 );
// // 				// 	mesh.scale.set( 0.3, 0.3, 0.3 );

// // 				// 	mesh.castShadow = true;
// // 				// 	mesh.receiveShadow = true;

// // 				// 	scene.add( mesh );

// // 				// } );


// // 				// Lights

// // 				scene.add( new THREE.AmbientLight( 0x777777 ) );

// // 				addShadowedLight( 1, 1, 1, 0xffffff, 1.35 );
// // 				addShadowedLight( 0.5, 1, -1, 0xffaa00, 1 );

// // 				// renderer

// // 				renderer = new THREE.WebGLRenderer( { antialias: true } );
// // 				renderer.setClearColor( scene.fog.color );
// // 				renderer.setPixelRatio( window.devicePixelRatio );
// // 				renderer.setSize( window.innerWidth, window.innerHeight );

// // 				renderer.gammaInput = true;
// // 				renderer.gammaOutput = true;

// // 				renderer.shadowMapEnabled = true;
// // 				renderer.shadowMapCullFace = THREE.CullFaceBack;

// // 				container.appendChild( renderer.domElement );

// // 				// stats

// // 				stats = new Stats();
// // 				stats.domElement.style.position = 'absolute';
// // 				stats.domElement.style.top = '0px';
// // 				container.appendChild( stats.domElement );

// // 				//

// // 				window.addEventListener( 'resize', onWindowResize, false );

// // 			}

// // 			function addShadowedLight( x, y, z, color, intensity ) {

// // 				var directionalLight = new THREE.DirectionalLight( color, intensity );
// // 				directionalLight.position.set( x, y, z )
// // 				scene.add( directionalLight );

// // 				directionalLight.castShadow = true;
// // 				// directionalLight.shadowCameraVisible = true;

// // 				var d = 1;
// // 				directionalLight.shadowCameraLeft = -d;
// // 				directionalLight.shadowCameraRight = d;
// // 				directionalLight.shadowCameraTop = d;
// // 				directionalLight.shadowCameraBottom = -d;

// // 				directionalLight.shadowCameraNear = 1;
// // 				directionalLight.shadowCameraFar = 4;

// // 				directionalLight.shadowMapWidth = 1024;
// // 				directionalLight.shadowMapHeight = 1024;

// // 				directionalLight.shadowBias = -0.005;
// // 				directionalLight.shadowDarkness = 0.15;

// // 			}

// // 			function onWindowResize() {

// // 				camera.aspect = window.innerWidth / window.innerHeight;
// // 				camera.updateProjectionMatrix();

// // 				renderer.setSize( window.innerWidth, window.innerHeight );

// // 			}

// // 			function animate() {

// // 				requestAnimationFrame( animate );

// // 				render();
// // 				stats.update();

// // 			}

// // 			function render() {

// // 				var timer = Date.now() * 0.0005;

// // 				camera.position.x = Math.cos( timer ) * 3;
// // 				camera.position.z = Math.sin( timer ) * 3;

// // 				camera.lookAt( cameraTarget );

// // 				renderer.render( scene, camera );

// // 			}

// var container, camera, scene, renderer;

// init();
// animate();

// function init(){
//     container=document.createElement('div');
//     document.body.appendChild(container);

//     camera=new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 1, 10000);
//     // camera.position.set(3, 50.5, 3);

//     scene=new THREE.Scene();

//     // object
//     var loader=new THREE.STLLoader();
//     // loader.addEventListener('load', function (event){
// 				loader.load( './assets/Bear_Robots.stl', function ( geometry ) {
//         // var geometry=event.content;
//         var material;
//            if (geometry.hasColors) {
//      material = new THREE.MeshPhongMaterial({ opacity: geometry.alpha, vertexColors: THREE.VertexColors });
//    } else { 
//         material=new THREE.MeshLambertMaterial({ ambient: 0xFBB917,color: 0x5f9ea0 });
//     }
//         var mesh=new THREE.Mesh(geometry, material);
//         scene.add(mesh);});

//     // STL file to be loaded
//     // loader.load('./stl/3knot.scad.stl');

//     // lights
//     // scene.add(new THREE.AmbientLight(0xffffff));

// 				// Lights

// 				scene.add( new THREE.AmbientLight( 0x777777 ) );

// 				addShadowedLight( 1, 1, 1, 0xffffff, 1.35 );
// 				addShadowedLight( 0.5, -1, -1, 0xfffff, 1 );

//     // var directionalLight=new THREE.DirectionalLight(0xffffff, 1);
//     // directionalLight.position=camera.position;
//     // scene.add(directionalLight);
// 			function addShadowedLight( x, y, z, color, intensity ) {

// 				var directionalLight = new THREE.DirectionalLight( color, intensity );
// 				directionalLight.position.set( x, y, z )
// 				scene.add( directionalLight );

// 				directionalLight.castShadow = true;
// 				// directionalLight.shadowCameraVisible = true;

// 				var d = 1;
// 				directionalLight.shadowCameraLeft = -d;
// 				directionalLight.shadowCameraRight = d;
// 				directionalLight.shadowCameraTop = d;
// 				directionalLight.shadowCameraBottom = -d;

// 				directionalLight.shadowCameraNear = 1;
// 				directionalLight.shadowCameraFar = 4;

// 				directionalLight.shadowMapWidth = 1024;
// 				directionalLight.shadowMapHeight = 1024;

// 				directionalLight.shadowBias = -0.005;
// 				directionalLight.shadowDarkness = 0.15;

// 			}
//     // renderer

//     renderer=new THREE.WebGLRenderer({ antialias: true });
//     renderer.setSize(window.innerWidth, window.innerHeight);

//     container.appendChild(renderer.domElement);

//     window.addEventListener('resize', onWindowResize, false);}

// // function addLight(x, y, z, color, intensity){
// //     var directionalLight=new THREE.DirectionalLight(color, intensity);
// //     directionalLight.position.set(x, y, z)
// //     scene.add(directionalLight);}

// function onWindowResize(){
//     camera.aspect=window.innerWidth / window.innerHeight;
//     camera.updateProjectionMatrix();
//     renderer.setSize(window.innerWidth, window.innerHeight);}

//   function animate(){
//       requestAnimationFrame(animate);
//       render();}

//   function render(){
//       // var timer=Date.now() * 0.0005;
//       var r=70;
//       // // camera.position.x=r*Math.cos(timer);
//       //  camera.position.x=0;
//       // camera.position.y=-150;
//       // camera.position.z=50;
// 				var timer = Date.now() * 0.0005;

// 				camera.position.x = r*Math.cos( timer ) * 5;
// 				camera.position.y = r*Math.cos( timer ) * 5;
// 				camera.position.z = r*Math.sin( timer ) * 5;
//       // camera.position.z=r*Math.sin(timer);
//       camera.lookAt(scene.position);
//       renderer.render(scene, camera);
//       renderer.setClearColor(0x000000, 1);}

// 	// if ( ! Detector.webgl ) Detector.addGetWebGLMessage();

// 	// 		var container, stats;

// 	// 		var camera, scene, renderer, objects;

// 	// 		init();
// 	// 		animate();

// 	// 		function init() {

// 	// 			container = document.createElement( 'div' );
// 	// 			document.body.appendChild( container );

// 	// 			camera = new THREE.PerspectiveCamera( 35, window.innerWidth / window.innerHeight, 1, 50 );
// 	// 			camera.position.set( 3, 0.5, 3 );

// 	// 			scene = new THREE.Scene();

// 	// 			scene.fog = new THREE.Fog( 0xffffff, 2, 15 );
// 	// 			// scene.fog.color.setHSV( 0.06, 0.2, 0.45 );

// 	// 			// Grid

// 	// 			var size = 20, step = 0.25;

// 	// 			var geometry = new THREE.Geometry();
// 	// 			var material = new THREE.LineBasicMaterial( { color: 0x000000 } );

// 	// 			for ( var i = - size; i <= size; i += step ) {

// 	// 				geometry.vertices.push( new THREE.Vector3( - size, - 0.04, i ) );
// 	// 				geometry.vertices.push( new THREE.Vector3(   size, - 0.04, i ) );

// 	// 				geometry.vertices.push( new THREE.Vector3( i, - 0.04, - size ) );
// 	// 				geometry.vertices.push( new THREE.Vector3( i, - 0.04,   size ) );

// 	// 			}

// 	// 			var line = new THREE.Line( geometry, material, THREE.LinePieces );
// 	// 			line.position.y = -0.46;
// 	// 			scene.add( line );

// 	// 			// Ground

// 	// 			var plane = new THREE.Mesh( new THREE.PlaneGeometry( 40, 40 ), new THREE.MeshPhongMaterial( { ambient: 0x999999, color: 0x999999, specular: 0x101010, perPixel: true } ) );
// 	// 			plane.rotation.x = -Math.PI/2;
// 	// 			plane.position.y = -0.5;
// 	// 			scene.add( plane );

// 	// 			plane.receiveShadow = true;

// 	// 			// Object

// 	// 			var loader = new THREE.STLLoader();
// 	// 			// loader.addEventListener( 'load', function ( event ) {
// 	// 			loader.load( './assets/Bear_Robots.stl', function ( geometry ) {

// 	// 				// var geometry = event.content;
// 	// 				// console.log(geometry);
// 	// 				var material = new THREE.MeshPhongMaterial( { ambient: 0xff5533, color: 0xff5533, specular: 0x111111, shininess: 200, perPixel: true } );
// 	// 				var mesh = new THREE.Mesh( geometry, material );

// 	// 				mesh.castShadow = true;
// 	// 				mesh.receiveShadow = true;

// 	// 				scene.add( mesh );

// 	// 			} );
// 	// 			// loader.load( './models/stl/slotted_disk.stl' );

// 	// 			// Lights

// 	// 			scene.add( new THREE.AmbientLight( 0x777777 ) );

// 	// 			addShadowedLight( 1, 1, 1, 0xffffff, 1.35 );
// 	// 			addShadowedLight( 0.5, 1, -1, 0xffaa00, 1 );

// 	// 			// renderer

// 	// 			renderer = new THREE.WebGLRenderer( { antialias: true, clearColor: 0x111111, clearAlpha: 1, alpha: false } );
// 	// 			renderer.setSize( window.innerWidth, window.innerHeight );

// 	// 			renderer.setClearColor( scene.fog.color, 1 );

// 	// 			renderer.gammaInput = true;
// 	// 			renderer.gammaOutput = true;
// 	// 			renderer.physicallyBasedShading = true;

// 	// 			renderer.shadowMapEnabled = true;
// 	// 			renderer.shadowMapCullFrontFaces = false;

// 	// 			container.appendChild( renderer.domElement );

// 	// 			// stats

// 	// 			stats = new Stats();
// 	// 			stats.domElement.style.position = 'absolute';
// 	// 			stats.domElement.style.top = '0px';
// 	// 			container.appendChild( stats.domElement );

// 	// 			//

// 	// 			window.addEventListener( 'resize', onWindowResize, false );

// 	// 		}

// 	// 		function addShadowedLight( x, y, z, color, intensity ) {

// 	// 			var directionalLight = new THREE.DirectionalLight( color, intensity );
// 	// 			directionalLight.position.set( x, y, z )
// 	// 			scene.add( directionalLight );

// 	// 			directionalLight.castShadow = true;
// 	// 			//directionalLight.shadowCameraVisible = true;

// 	// 			var d = 1;
// 	// 			directionalLight.shadowCameraLeft = -d;
// 	// 			directionalLight.shadowCameraRight = d;
// 	// 			directionalLight.shadowCameraTop = d;
// 	// 			directionalLight.shadowCameraBottom = -d;

// 	// 			directionalLight.shadowCameraNear = 1;
// 	// 			directionalLight.shadowCameraFar = 4;

// 	// 			directionalLight.shadowMapWidth = 2048;
// 	// 			directionalLight.shadowMapHeight = 2048;

// 	// 			directionalLight.shadowBias = -0.005;
// 	// 			directionalLight.shadowDarkness = 0.15;

// 	// 		}

// 	// 		function onWindowResize() {

// 	// 			camera.aspect = window.innerWidth / window.innerHeight;
// 	// 			camera.updateProjectionMatrix();

// 	// 			renderer.setSize( window.innerWidth, window.innerHeight );

// 	// 		}

// 	// 		//

// 	// 		function animate() {

// 	// 			requestAnimationFrame( animate );

// 	// 			render();
// 	// 			stats.update();

// 	// 		}

// 	// 		function render() {

// 	// 			var timer = Date.now() * 0.0005;

// 	// 			camera.position.x = Math.cos( timer ) * 5;
// 	// 			camera.position.z = Math.sin( timer ) * 5;

// 	// 			camera.lookAt( scene.position );

// 	// 			renderer.render( scene, camera );

// 	// 		}

//         // var camera, scene, renderer,
//         //     geometry, material, mesh, light1, stats;

//         //     function trim (str) {
//         //         str = str.replace(/^\s+/, '');
//         //         for (var i = str.length - 1; i >= 0; i--) {
//         //             if (/\S/.test(str.charAt(i))) {
//         //                 str = str.substring(0, i + 1);
//         //                 break;
//         //             }
//         //         }
//         //         return str;
//         //     }

//         //     // Notes:
//         //     // - STL file format: http://en.wikipedia.org/wiki/STL_(file_format)
//         //     // - 80 byte unused header
//         //     // - All binary STLs are assumed to be little endian, as per wiki doc
//         //     var parseStlBinary = function(stl) {
//         //         var geo = new THREE.Geometry();
//         //         var dv = new DataView(stl, 80); // 80 == unused header
//         //         var isLittleEndian = true;
//         //         var triangles = dv.getUint32(0, isLittleEndian); 

//         //         // console.log('arraybuffer length:  ' + stl.byteLength);
//         //         // console.log('number of triangles: ' + triangles);

//         //         var offset = 4;
//         //         for (var i = 0; i < triangles; i++) {
//         //             // Get the normal for this triangle
//         //             var normal = new THREE.Vector3(
//         //                 dv.getFloat32(offset, isLittleEndian),
//         //                 dv.getFloat32(offset+4, isLittleEndian),
//         //                 dv.getFloat32(offset+8, isLittleEndian)
//         //             );
//         //             offset += 12;

//         //             // Get all 3 vertices for this triangle
//         //             for (var j = 0; j < 3; j++) {
//         //                 geo.vertices.push(
//         //                     new THREE.Vector3(
//         //                         dv.getFloat32(offset, isLittleEndian),
//         //                         dv.getFloat32(offset+4, isLittleEndian),
//         //                         dv.getFloat32(offset+8, isLittleEndian)
//         //                     )
//         //                 );
//         //                 offset += 12
//         //             }

//         //             // there's also a Uint16 "attribute byte count" that we
//         //             // don't need, it should always be zero.
//         //             offset += 2;   

//         //             // Create a new face for from the vertices and the normal             
//         //             geo.faces.push(new THREE.Face3(i*3, i*3+1, i*3+2, normal));
//         //         }

//         //         // The binary STL I'm testing with seems to have all
//         //         // zeroes for the normals, unlike its ASCII counterpart.
//         //         // We can use three.js to compute the normals for us, though,
//         //         // once we've assembled our geometry. This is a relatively 
//         //         // expensive operation, but only needs to be done once.
//         //         geo.computeFaceNormals();

//         //         mesh = new THREE.Mesh( 
//         //             geo,
//         //             // new THREE.MeshNormalMaterial({
//         //             //     overdraw:true
//         //             // }
//         //             new THREE.MeshLambertMaterial({
//         //                 overdraw:true,
//         //                 color: 0xaa0000,
//         //                 shading: THREE.FlatShading
//         //             }
//         //         ));
//         //         scene.add(mesh);

//         //         stl = null;
//         //     };  

//         //     var parseStl = function(stl) {
//         //         var state = '';
//         //         var lines = stl.split('\n');
//         //         var geo = new THREE.Geometry();
//         //         var name, parts, line, normal, done, vertices = [];
//         //         var vCount = 0;
//         //         stl = null;

//         //         for (var len = lines.length, i = 0; i < len; i++) {
//         //             if (done) {
//         //                 break;
//         //             }
//         //             line = trim(lines[i]);
//         //             parts = line.split(' ');
//         //             switch (state) {
//         //                 case '':
//         //                     if (parts[0] !== 'solid') {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "solid"');
//         //                         return;
//         //                     } else {
//         //                         name = parts[1];
//         //                         state = 'solid';
//         //                     }
//         //                     break;
//         //                 case 'solid':
//         //                     if (parts[0] !== 'facet' || parts[1] !== 'normal') {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "facet normal"');
//         //                         return;
//         //                     } else {
//         //                         normal = [
//         //                             parseFloat(parts[2]), 
//         //                             parseFloat(parts[3]), 
//         //                             parseFloat(parts[4])
//         //                         ];
//         //                         state = 'facet normal';
//         //                     }
//         //                     break;
//         //                 case 'facet normal':
//         //                     if (parts[0] !== 'outer' || parts[1] !== 'loop') {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "outer loop"');
//         //                         return;
//         //                     } else {
//         //                         state = 'vertex';
//         //                     }
//         //                     break;
//         //                 case 'vertex': 
//         //                     if (parts[0] === 'vertex') {
//         //                         geo.vertices.push(new THREE.Vector3(
//         //                             parseFloat(parts[1]),
//         //                             parseFloat(parts[2]),
//         //                             parseFloat(parts[3])
//         //                         ));
//         //                     } else if (parts[0] === 'endloop') {
//         //                         geo.faces.push( new THREE.Face3( vCount*3, vCount*3+1, vCount*3+2, new THREE.Vector3(normal[0], normal[1], normal[2]) ) );
//         //                         vCount++;
//         //                         state = 'endloop';
//         //                     } else {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "vertex" or "endloop"');
//         //                         return;
//         //                     }
//         //                     break;
//         //                 case 'endloop':
//         //                     if (parts[0] !== 'endfacet') {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "endfacet"');
//         //                         return;
//         //                     } else {
//         //                         state = 'endfacet';
//         //                     }
//         //                     break;
//         //                 case 'endfacet':
//         //                     if (parts[0] === 'endsolid') {
//         //                         //mesh = new THREE.Mesh( geo, new THREE.MeshNormalMaterial({overdraw:true}));
//         //                         mesh = new THREE.Mesh( 
//         //                             geo, 
//         //                             new THREE.MeshLambertMaterial({
//         //                                 overdraw:true,
//         //                                 color: 0xaa0000,
//         //                                 shading: THREE.FlatShading
//         //                             }
//         //                         ));
//         //                         scene.add(mesh);
//         //                         done = true;
//         //                     } else if (parts[0] === 'facet' && parts[1] === 'normal') {
//         //                         normal = [
//         //                             parseFloat(parts[2]), 
//         //                             parseFloat(parts[3]), 
//         //                             parseFloat(parts[4])
//         //                         ];
//         //                         if (vCount % 1000 === 0) {
//         //                             console.log(normal);
//         //                         }
//         //                         state = 'facet normal';
//         //                     } else {
//         //                         console.error(line);
//         //                         console.error('Invalid state "' + parts[0] + '", should be "endsolid" or "facet normal"');
//         //                         return;
//         //                     }
//         //                     break;
//         //                 default:
//         //                     console.error('Invalid state "' + state + '"');
//         //                     break;
//         //             }
//         //         }
//         //     };

    

//         //     init();
//         //     animate();

//         //     function init() {

//         //         //Detector.addGetWebGLMessage();

//         //         scene = new THREE.Scene();

//         //         camera = new THREE.PerspectiveCamera( 75, window.innerWidth / window.innerHeight, 1, 10000 );
//         //         camera.position.z = 150;
//         //         camera.position.y = 0;
//         //         scene.add( camera );

//         //         var directionalLight = new THREE.DirectionalLight( 0xffffff );
//         //         directionalLight.position.x = 0; 
//         //         directionalLight.position.y = 0; 
//         //         directionalLight.position.z = 1; 
//         //         directionalLight.position.normalize();
//         //         scene.add( directionalLight );

//         //         var xhr = new XMLHttpRequest();
//         //         xhr.onreadystatechange = function () {
//         //             if ( xhr.readyState == 4 ) {
//         //                 if ( xhr.status == 200 || xhr.status == 0 ) {
//         //                     var rep = xhr.response; // || xhr.mozResponseArrayBuffer;
//         //                     console.log(rep);
//         //                     parseStlBinary(rep);
//         //                     //parseStl(xhr.responseText);
//         //                     mesh.rotation.x = 5;
//         //                     mesh.rotation.z = .25;
//         //                     console.log('done parsing');
//         //                 }
//         //             }
//         //         }
//         //         xhr.onerror = function(e) {
//         //             console.log(e);
//         //         }
        
//         //         xhr.open( "GET", './assets/Bear_Robots.stl', true );
//         //         xhr.responseType = "arraybuffer";
//         //         //xhr.setRequestHeader("Accept","text/plain");
//         //         //xhr.setRequestHeader("Content-Type","text/plain");
//         //         //xhr.setRequestHeader('charset', 'x-user-defined');
//         //         xhr.send( null );

//         //         renderer = new THREE.WebGLRenderer(); //new THREE.CanvasRenderer();
//         //         renderer.setSize( window.innerWidth, window.innerHeight );

//         //         document.body.appendChild( renderer.domElement );

//         //         stats = new Stats();
//         //         stats.domElement.style.position = 'absolute';
//         //         stats.domElement.style.top = '0px';
//         //         document.body.appendChild(stats.domElement);
//         //     }

//         //     function animate() {

//         //         // note: three.js includes requestAnimationFrame shim
//         //         requestAnimationFrame( animate );
//         //         render();
//         //         stats.update();

//         //     }

//         //     function render() {

//         //         // mesh.rotation.x += 0.01;
//         //         // if (mesh) {
//         //         //     mesh.rotation.z += 0.02;
//         //         // }
//         //         //light1.position.z -= 1;

//         //         renderer.render( scene, camera );

//         //     }	
// });