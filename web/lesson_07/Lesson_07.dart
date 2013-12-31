
import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math';


/**
 * based on:
 * http://learningwebgl.com/blog/?p=571
 *
 * NOTE: To run this example you have to open in on a webserver (url starting with http:// NOT file:///)!
 */
class Lesson07 {
  
  CanvasElement _canvas;
  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;
  
  webgl.Texture _texture;
  
  webgl.Buffer _cubeVertexTextureCoordBuffer;
  webgl.Buffer _cubeVertexPositionBuffer;
  webgl.Buffer _cubeVertexIndexBuffer;
  webgl.Buffer _cubeVertexNormalBuffer;
  
  Matrix4 _pMatrix;
  Matrix4 _mvMatrix;
  Queue<Matrix4> _mvMatrixStack;
  
  int _aVertexPosition;
  int _aTextureCoord;
  int _aVertexNormal;
  webgl.UniformLocation _uPMatrix;
  webgl.UniformLocation _uMVMatrix;
  webgl.UniformLocation _uNMatrix;
  webgl.UniformLocation _uSampler;
  webgl.UniformLocation _uUseLighting;
  webgl.UniformLocation _uLightDirection;
  webgl.UniformLocation _uAmbientColor;
  webgl.UniformLocation _uDirectionalColor;
  
  InputElement _elmLighting;
  InputElement _elmAmbientR, _elmAmbientG, _elmAmbientB;
  InputElement _elmLightDirectionX, _elmLightDirectionY, _elmLightDirectionZ;
  InputElement _elmDirectionalR, _elmDirectionalG, _elmDirectionalB;
  
  double _xRot = 0.0, _xSpeed = 5.0,
      _yRot = 0.0, _ySpeed = 5.0,
      _zPos = -5.0;
  
  int _filter = 0;
  double _lastTime = 0.0;
  
  List<bool> _currentlyPressedKeys;
  
  var _requestAnimationFrame;
  
  
  Lesson07(CanvasElement canvas) {
    // weird, but without specifying size this array throws exception on []
    _currentlyPressedKeys = new List<bool>(128);
    for(int i=0; i<128; i++) _currentlyPressedKeys[i]=false;
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");
    
    _mvMatrix = new Matrix4.identity();
    _pMatrix = new Matrix4.identity();
    
    _initShaders();
    _initBuffers();
    _initTexture();
    

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);
    
    window.onKeyUp.listen(this._handleKeyUp);
    window.onKeyDown.listen(this._handleKeyDown);
    
    _elmLighting = querySelector("#lighting");
    _elmAmbientR = querySelector("#ambientR");
    _elmAmbientG = querySelector("#ambientG");
    _elmAmbientB = querySelector("#ambientB");
    _elmLightDirectionX = querySelector("#lightDirectionX");
    _elmLightDirectionY = querySelector("#lightDirectionY");
    _elmLightDirectionZ = querySelector("#lightDirectionZ");
    _elmDirectionalR = querySelector("#directionalR");
    _elmDirectionalG = querySelector("#directionalG");
    _elmDirectionalB = querySelector("#directionalB");
  }
  

  void _initShaders() {
    // vertex shader source code. uPosition is our variable that we'll
    // use to create animation
    String vsSource = """
    attribute vec3 aVertexPosition;
    attribute vec2 aTextureCoord;
    attribute vec3 aVertexNormal;
  
    uniform mat4 uMVMatrix;
    uniform mat4 uPMatrix;
    uniform mat3 uNMatrix;

    uniform vec3 uAmbientColor;

    uniform vec3 uLightingDirection;
    uniform vec3 uDirectionalColor;

    uniform bool uUseLighting;
  
    varying vec2 vTextureCoord;
    varying vec3 vLightWeighting;
  
    void main(void) {
      gl_Position = uPMatrix * uMVMatrix * vec4(aVertexPosition, 1.0);
      vTextureCoord = aTextureCoord;
      if(!uUseLighting)
      {
         vLightWeighting = vec3(1.0, 1.0, 1.0);
      } else
      {
         vec3 transformedNormal = uNMatrix * aVertexNormal;
         float directionalLightWeighting = max(dot(transformedNormal, uLightingDirection), 0.0);
         vLightWeighting = uAmbientColor + uDirectionalColor*directionalLightWeighting;
      }
    }
    """;
    
    // fragment shader source code. uColor is our variable that we'll
    // use to animate color
    String fsSource = """
    precision mediump float;

    varying vec2 vTextureCoord;
    varying vec3 vLightWeighting;

    uniform sampler2D uSampler;

    void main(void) {
      vec4 textureColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
      gl_FragColor = vec4(textureColor.rgb * vLightWeighting, textureColor.a);
    }
    """;
    
    // vertex shader compilation
    webgl.Shader vs = _gl.createShader(webgl.RenderingContext.VERTEX_SHADER);
    _gl.shaderSource(vs, vsSource);
    _gl.compileShader(vs);
    
    // fragment shader compilation
    webgl.Shader fs = _gl.createShader(webgl.RenderingContext.FRAGMENT_SHADER);
    _gl.shaderSource(fs, fsSource);
    _gl.compileShader(fs);
    
    // attach shaders to a WebGL program
    _shaderProgram = _gl.createProgram();
    _gl.attachShader(_shaderProgram, vs);
    _gl.attachShader(_shaderProgram, fs);
    _gl.linkProgram(_shaderProgram);
    _gl.useProgram(_shaderProgram);
    
    /**
     * Check if shaders were compiled properly. This is probably the most painful part
     * since there's no way to "debug" shader compilation
     */
    if (!_gl.getShaderParameter(vs, webgl.RenderingContext.COMPILE_STATUS)) { 
      print(_gl.getShaderInfoLog(vs));
    }
    
    if (!_gl.getShaderParameter(fs, webgl.RenderingContext.COMPILE_STATUS)) { 
      print(_gl.getShaderInfoLog(fs));
    }
    
    if (!_gl.getProgramParameter(_shaderProgram, webgl.RenderingContext.LINK_STATUS)) { 
      print(_gl.getProgramInfoLog(_shaderProgram));
    }
    
    _aVertexPosition = _gl.getAttribLocation(_shaderProgram, "aVertexPosition");
    _gl.enableVertexAttribArray(_aVertexPosition);
    
    _aTextureCoord = _gl.getAttribLocation(_shaderProgram, "aTextureCoord");
    _gl.enableVertexAttribArray(_aTextureCoord);
    
    _aVertexNormal = _gl.getAttribLocation(_shaderProgram, "aVertexNormal");
    _gl.enableVertexAttribArray(_aVertexNormal);
    
    _uPMatrix = _gl.getUniformLocation(_shaderProgram, "uPMatrix");
    _uMVMatrix = _gl.getUniformLocation(_shaderProgram, "uMVMatrix");
    _uNMatrix = _gl.getUniformLocation(_shaderProgram, "uNMatrix");
    _uSampler = _gl.getUniformLocation(_shaderProgram, "uSampler");
    _uUseLighting = _gl.getUniformLocation(_shaderProgram, "uUseLighting");
    _uAmbientColor = _gl.getUniformLocation(_shaderProgram, "uAmbientColor");
    _uLightDirection = _gl.getUniformLocation(_shaderProgram, "uLightingDirection");
    _uDirectionalColor = _gl.getUniformLocation(_shaderProgram, "uDirectionalColor");

  }
  
  void _initBuffers() {
    // variables to store verticies, tecture coordinates and colors
    List<double> vertices, textureCoords, vertexNormals, colors;
    
    
    // create square
    _cubeVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexPositionBuffer);
    // fill "current buffer" with triangle verticies
    vertices = [
        // Front face
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,
        
        // Back face
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,
        
        // Top face
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
        
        // Bottom face
        -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,
        
        // Right face
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0,  1.0,  1.0,
         1.0, -1.0,  1.0,
        
        // Left face
        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertices), webgl.RenderingContext.STATIC_DRAW);
    
    _cubeVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexTextureCoordBuffer);
    textureCoords = [
        // Front face
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
      
        // Back face
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
      
        // Top face
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
      
        // Bottom face
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
      
        // Right face
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
      
        // Left face
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoords), webgl.RenderingContext.STATIC_DRAW);
    
    _cubeVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _cubeVertexIndexBuffer);
    List<int> _cubeVertexIndices = [
         0,  1,  2,    0,  2,  3, // Front face
         4,  5,  6,    4,  6,  7, // Back face
         8,  9, 10,    8, 10, 11, // Top face
        12, 13, 14,   12, 14, 15, // Bottom face
        16, 17, 18,   16, 18, 19, // Right face
        20, 21, 22,   20, 22, 23  // Left face
    ];
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(_cubeVertexIndices), webgl.RenderingContext.STATIC_DRAW);
    
    
    _cubeVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexNormalBuffer);
    vertexNormals = [
      // Front face
       0.0,  0.0,  1.0,
       0.0,  0.0,  1.0,
       0.0,  0.0,  1.0,
       0.0,  0.0,  1.0,

      // Back face
       0.0,  0.0, -1.0,
       0.0,  0.0, -1.0,
       0.0,  0.0, -1.0,
       0.0,  0.0, -1.0,

      // Top face
       0.0,  1.0,  0.0,
       0.0,  1.0,  0.0,
       0.0,  1.0,  0.0,
       0.0,  1.0,  0.0,

      // Bottom face
       0.0, -1.0,  0.0,
       0.0, -1.0,  0.0,
       0.0, -1.0,  0.0,
       0.0, -1.0,  0.0,

      // Right face
       1.0,  0.0,  0.0,
       1.0,  0.0,  0.0,
       1.0,  0.0,  0.0,
       1.0,  0.0,  0.0,

      // Left face
      -1.0,  0.0,  0.0,
      -1.0,  0.0,  0.0,
      -1.0,  0.0,  0.0,
      -1.0,  0.0,  0.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexNormals), webgl.RenderingContext.STATIC_DRAW);

  }
  
  void _initTexture() {
    _texture = _gl.createTexture();
    ImageElement image = new Element.tag('img');
    image.onLoad.listen((Event e) { _handleLoadedTexture(_texture, image); });
    image.src = "./crate.gif";
  }
  
  void _handleLoadedTexture(webgl.Texture texture, ImageElement img) {
    _gl.pixelStorei(webgl.RenderingContext.UNPACK_FLIP_Y_WEBGL, 1); // second argument must be an int (no boolean)
    
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, texture);
    _gl.texImage2D(webgl.RenderingContext.TEXTURE_2D, 0, webgl.RenderingContext.RGBA, webgl.RenderingContext.RGBA, webgl.RenderingContext.UNSIGNED_BYTE, img);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MAG_FILTER, webgl.RenderingContext.LINEAR);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MIN_FILTER, webgl.RenderingContext.LINEAR_MIPMAP_NEAREST);
    _gl.generateMipmap(webgl.RenderingContext.TEXTURE_2D);
    
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
  }
  
  void _setMatrixUniforms() {
    Float32List tmpList = new Float32List(16);
    Float32List tmpList9 = new Float32List(9);
    
    _pMatrix.copyIntoArray(tmpList);
    _gl.uniformMatrix4fv(_uPMatrix, false, tmpList);
    
    _mvMatrix.copyIntoArray(tmpList);
    _gl.uniformMatrix4fv(_uMVMatrix, false, tmpList);
    
    Matrix4 mvInverse = new Matrix4.identity();
    mvInverse.copyInverse(_mvMatrix);
    Matrix3 normalMatrix = mvInverse.getRotation();

    
  //  Matrix3 normalMatrix = _mvMatrix.toInverseMat3();
    normalMatrix.transpose();
    normalMatrix.copyIntoArray(tmpList9);
    _gl.uniformMatrix3fv(_uNMatrix, false, tmpList9);
  }
  
  bool render(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);
    
    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
//    Matrix4.perspective(45, _viewportWidth / _viewportHeight, 0.1, 100.0, _pMatrix);
    _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);
    
    _mvMatrix = new Matrix4.identity();
    _mvMatrix.translate(new Vector3(0.0, 0.0, _zPos));

    _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(_xRot));
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(_yRot));
    //_mvMatrix.rotate(_degToRad(_zRot), new Vector3.fromList([0, 0, 1]));
    
    // verticies
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);
    
    // texture
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);
    
    // light
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);


    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _texture);
    //_gl.uniform1i(_uSamplerUniform, 0);
    
    // draw lighting?
    _gl.uniform1i(_uUseLighting, _elmLighting.checked ? 1 : 0); // must be int, not bool
    
    num aR=0.0;
    num aG=0.0;
    num aB=0.0;
    num dR=0.0;
    num dG=0.0;
    num dB=0.0;
    
    num r = 0.0;
    num g = 0.0;
    num b = 0.0;
    
    try
    {
    aR = double.parse(_elmAmbientR.value);
    aG = double.parse(_elmAmbientG.value);
    aB = double.parse(_elmAmbientB.value);
    dR = double.parse(_elmLightDirectionX.value);
    dG = double.parse(_elmLightDirectionY.value);
    dB = double.parse(_elmLightDirectionZ.value);
    r = double.parse(_elmDirectionalR.value);
    g = double.parse(_elmDirectionalG.value);
    b = double.parse(_elmDirectionalB.value);
    } catch(exception)
    {}
    
    
    if (_elmLighting.checked) {
      _gl.uniform3f(
        _uAmbientColor,
        aR,
        aG,
        aB
      );
      
      Vector3 lightingDirection = new Vector3(
        dR,
        dG,
        dB
      );
      Vector3 adjustedLD = new Vector3.zero();
      lightingDirection.normalizeInto(adjustedLD);
      adjustedLD.scale(-1.0);
      //Float32List f32LD = new Float32List(3);
      //adjustedLD.copyIntoArray(f32LD);
      //_gl.uniform3fv(_uLightDirection, f32LD);
      _gl.uniform3f(_uLightDirection, adjustedLD.x, adjustedLD.y, adjustedLD.z);

      
      _gl.uniform3f(
        _uDirectionalColor, r, g, b
      );
    }
    
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _cubeVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, 36, webgl.RenderingContext.UNSIGNED_SHORT, 0);
    
    // rotate
    _animate(time);
    _handleKeys();
    
    // keep drawing
    _renderFrame();
  }
  
  void _handleKeyDown(KeyboardEvent event) {
    if( (event.keyCode > 0) && (event.keyCode < 128))
    _currentlyPressedKeys[event.keyCode] = true;
  }
  
  void _handleKeyUp(KeyboardEvent event) {
    if( (event.keyCode > 0) && (event.keyCode < 128))
    _currentlyPressedKeys[event.keyCode] = false;
  }
  
  void _animate(double time) {
    if (_lastTime != 0) {
        double animationStep = time - _lastTime;

        _xRot += (90 * animationStep * _xSpeed) / 5000.0;
        _yRot += (90 * animationStep * _ySpeed) / 5000.0;
    }
    _lastTime = time;
  }
  
  void _handleKeys() {
    if (_currentlyPressedKeys[KeyCode.NUM_FIVE]) {
      // Page Up
      _zPos -= 0.05;
    }
    if (_currentlyPressedKeys[KeyCode.NUM_ZERO]) {
      // Page Down
      _zPos += 0.05;
    }
    if (_currentlyPressedKeys[KeyCode.NUM_EIGHT]) {
      // Left cursor key
      _ySpeed -= 1;
    }
    if (_currentlyPressedKeys[KeyCode.NUM_TWO]) {
      // Right cursor key
      _ySpeed += 1;
    }
    if (_currentlyPressedKeys[KeyCode.NUM_FOUR]) {
      // Up cursor key
      _xSpeed -= 1;
    }
    if (_currentlyPressedKeys[KeyCode.NUM_SIX]) {
      // Down cursor key
      _xSpeed += 1;
    }
  }
  
  double _degToRad(double degrees) {
    return degrees * PI / 180;
  }
  
  void start() {
    this._renderFrame();
  }
  
  void _renderFrame() {
    window.requestAnimationFrame((num time) { this.render(time); });
  }
  
}

void main() {
  Lesson07 lesson = new Lesson07(querySelector('#drawHere'));
  lesson.start();
}
