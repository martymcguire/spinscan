import processing.serial.*;
import processing.video.*;
import hypermedia.video.*;
import controlP5.*;
import processing.opengl.*;
import com.hardcorepawn.*;

SuperPoint p;
ControlP5 controlP5;
Serial serial;
Capture cam;
MovieMaker movie;
OpenCV opencv;
SteppedMovie textureMovie;
SteppedMovie laserMovie;
ArrayList pointList = new ArrayList();
ArrayList normalList = new ArrayList();
ArrayList colorList = new ArrayList();
PrintWriter plyFile;

int width = 860;
int height = 720;
int framerate = 13;
int threshold = 10; // 30
int frame = 1;

int videoWidth = 640;
int videoHeight = 480;
//int videoWidth = 800;
//int videoHeight = 600;

String serialResponse = null;
boolean recording = false;
String recordingType = null;
boolean laserScanLoaded = false;
boolean textureScanLoaded = false;
boolean processing = false;

String serialPort = null;
String camPort = null;

boolean serialConnected = false;
boolean camConnected = false;

String[] serialPorts;
String[] camPorts;
int command_start_time = 0;
int command_end_time = 0;

ListBox serialList;
ListBox camList;
CheckBox laserBox;
Textfield camHFOVField;
Textfield camVFOVField;
Textfield camDistanceField;
Textfield laserOffsetField;

String textureFilename = "data/texture.mov";
String laserFilename = "data/laser.mov";
String plyFilename = null;

// degrees 56 zoom in 75 zoom out
float camHFOV = 75.0;
// degrees
float camVFOV = (camHFOV * 4.0) / 5.0;
// from camera to center of table in mm
float camDistance = 304.8; // 1 foot
// degrees
float laserOffset = 45.0; // 15? 45?
int frameSkip = 1;
int pointSkip = 1;
float radiansToDegrees = 180.0 / 3.14159;
float degreesToRadians = 3.14159 / 180.0;

int avgHorizontal = 10;
int avgVertical = 10;

int brightness = 0;
int contrast = 0;

PImage textureImage;
PImage laserImage;
PImage lineImage;

void setup() {
  camPorts = Capture.list();

  size(width, height, OPENGL);
  p = new SuperPoint(this);
//  smooth();
  frameRate(framerate);

  opencv = new OpenCV(this);
  opencv.allocate(videoWidth, videoHeight);

  controlP5 = new ControlP5(this);

  laserBox = controlP5.addCheckBox("laserBox", 10, 100);
  laserBox.setItemsPerRow(1);
  laserBox.setSpacingColumn(30);
  laserBox.setSpacingRow(10);
  laserBox.addItem("Laser", 1);

  controlP5.addButton("textureScan", 0, 10, 120, 90, 15).captionLabel().set("Record Texture");
  controlP5.addButton("openTextureScan", 0, 230, height-25, 100, 15).captionLabel().set("Open Texture Scan");

  controlP5.addButton("laserScan", 0, 120, 120, 90, 15).captionLabel().set("Record Laser");
  controlP5.addButton("openLaserScan", 0, 550, height-25, 100, 15).captionLabel().set("Open Laser Scan");

  controlP5.addSlider("brightness", -128, 128, contrast, 10, 60, 150, 10);
  Slider contrastSlider = (Slider)controlP5.controller("contrast");
  
  controlP5.addSlider("contrast", -128, 128, contrast, 10, 80, 150, 10);
  Slider brightnessSlider = (Slider)controlP5.controller("brightness");

  camList = controlP5.addListBox("camList", 10, 50, 200, 120);
  camList.setItemHeight(15);
  camList.setBarHeight(15);
  camList.captionLabel().set("Select Camera");
  camList.captionLabel().style().marginTop = 3;
  for (int i = 0; i < camPorts.length; i++) {
    camList.addItem(camPorts[i], i);
  }
  camList.close();

  serialPorts = Serial.list();
  serialList = controlP5.addListBox("serialList", 10, 30, 200, 120);
  serialList.setItemHeight(15);
  serialList.setBarHeight(15);
  serialList.captionLabel().set("Select Serial Port");
  serialList.captionLabel().style().marginTop = 3;
  for (int i = 0; i < serialPorts.length; i++) {
    serialList.addItem(serialPorts[i], i);
  }
  serialList.close();

  camHFOVField = controlP5.addTextfield("camHFOV", 10, 200, 90, 15);
  camHFOVField.captionLabel().set("Camera HFOV (deg)");
  camHFOVField.setText(str(camHFOV));

  camVFOVField = controlP5.addTextfield("camVFOV", 120, 200, 90, 15);
  camVFOVField.captionLabel().set("Camera VFOV (deg)");
  camVFOVField.setText(str(camVFOV));

  camDistanceField = controlP5.addTextfield("camDistance", 10, 240, 90, 15);
  camDistanceField.captionLabel().set("Camera Distance (mm)");
  camDistanceField.setText(str(camDistance));

  laserOffsetField = controlP5.addTextfield("laserOffset", 10, 280, 90, 15);
  laserOffsetField.captionLabel().set("Laser Offset (deg)");
  laserOffsetField.setText(str(laserOffset));

  controlP5.addButton("processScans", 0, 10, 320, 90, 15).captionLabel().set("Process Scans!");

  controlP5.addButton("testSpin", 0, 10, 360, 90, 15).captionLabel().set("Test Spin");
  
  //loadTextureScan();
  //loadLaserScan();
}

void draw() {
  background(color(0,0,0));

  if (camConnected) {
    cam.read();
    PImage camImage = cam.get();
    opencv.copy(camImage);

    opencv.brightness(brightness);
    opencv.contrast(contrast);

    PImage opencvImage = opencv.image();

    if (recording) {
      movie.addFrame(opencvImage.pixels, opencvImage.width, opencvImage.height);
    } else {
      // don't waste cpu cycles while recording?
      image(opencvImage, 220, 0, 640, 480);
    }

    // main video window crosshair
    stroke(255);
    line(640/2+220, 0, 640/2+220, 480);
    line(220, 480/2, 640+220, 480/2);
  }

  if (processing) {
    if (laserMovie.done()) {
      plyFile = createWriter(plyFilename);
      plyFile.println("ply");
      plyFile.println("format ascii 1.0");
      plyFile.println("comment Made with spinscan!");
      plyFile.println("element vertex " + pointList.size());
      plyFile.println("property float x");
      plyFile.println("property float y");
      plyFile.println("property float z");
      plyFile.println("property float nx");
      plyFile.println("property float ny");
      plyFile.println("property float nz");
      plyFile.println("property uchar red");
      plyFile.println("property uchar green");
      plyFile.println("property uchar blue");
      plyFile.println("end_header");
      
      for (int i = 0; i < pointList.size(); i++) {
        float[] thisPoint = (float[]) pointList.get(i);
        float[] thisNormal = (float[]) normalList.get(i);
        int[] thisColor = (int[]) colorList.get(i);
        plyFile.println(thisPoint[0] + " " + thisPoint[1] + " " + thisPoint[2] + " " + thisNormal[0] + " " + thisNormal[1] + " " + thisNormal[2] + " " + thisColor[0] + " " + thisColor[1] + " " + thisColor[2]);
//        println("Writing line: " + i);
      }

      plyFile.flush();
      plyFile.close();
      
      println("Finished!");
      processing = false;
    } else {
      processScanFrame();
      frame += frameSkip;
//      frame++;
    }
    
//    image(laserImage, 220, 0);
  }
  
  if (textureScanLoaded) {
    image(textureMovie, 220, 480, 320, 240);
  }

  if (laserScanLoaded) {
    image(laserImage, 540, 480, 320, 240);
  }

  // window outlines
  stroke(50);
  line(220, 0, 220, height);
  line(220, 480, width, 480);
  line(540, 480, 540, height);
  
//  controlP5.draw();

  pushMatrix();
  translate(220+((width-220)/2),240/4);
  if (!processing) {
    rotateY(frameCount/50.0);
  }
  p.draw(1);
  popMatrix();
}

void controlEvent(ControlEvent theEvent) {
  if (theEvent.isGroup()) {
    // an event from a group e.g. scrollList
    String groupName = theEvent.group().name();
    float groupValue = theEvent.group().value();
    
    if (groupName == "serialList") {
      serialPort = serialPorts[int(groupValue)];
      serialList.captionLabel().set(serialPort);
      serialList.close();
      serialConnect();
    } else if (groupName == "camList") {
      camPort = camPorts[int(groupValue)];
      camList.captionLabel().set(camPort);
      camList.close();
      camConnect();
    } else if (groupName == "laserBox") {
      if (theEvent.group().arrayValue()[0] == 1.0) {
        laser(true);
      } else {
        laser(false);
      }
    } else {
      println("ERROR: Unknown group " + groupName);
    }
  }
}

void serialEvent(Serial serial) {
  serialResponse = serial.readStringUntil('\n');
  command_end_time = millis();

  if (recording) {
    recording = false;
    movie.finish();
    delay(50);
    if (recordingType == "texture") {
      loadTextureScan();
    } else {
      loadLaserScan();
    }
    recordingType = null;
    laser(false);
  }

  println("RECEIVED: " + serialResponse);
  println("COMMAND TOOK: " + ((command_end_time - command_start_time)/1000) + " seconds\n");
}

public void loadTextureScan() {
  textureMovie = new SteppedMovie(this, textureFilename);
  textureMovie.precalcFrameTimes();
  println("textureScan frame count: " + textureMovie.getFrameCount());
  delay(50);
  textureMovie.read();
  textureImage = textureMovie.get();
  textureScanLoaded = true;
}

public void loadLaserScan() {
  laserMovie = new SteppedMovie(this, laserFilename);
  laserMovie.precalcFrameTimes();
  println("laserScan frame count: " + laserMovie.getFrameCount());
  delay(50);
  laserMovie.read();
  laserImage = laserMovie.get();
  laserScanLoaded = true;
}

public void laser(boolean on) {
  command_start_time = millis();

  if (serialConnected && !recording) {
    if (on) {
      serial.write('1');
    } else {
      serial.write('0');
    }
  }
}

public void laserScan(int theValue) {
  if (serialConnected) {
    laserFilename = selectOutput("Save laser .mov to..."); 
    if (laserFilename == null) {
      println("ERROR: No laser output file was selected");
    } else {
      // make sure the laser is really on!
      command_start_time = millis();
      laser(true);
      delay(100);
      movie = new MovieMaker(this, videoWidth, videoHeight, laserFilename, framerate, MovieMaker.VIDEO, MovieMaker.LOSSLESS);
      command_start_time = millis();
      serial.write('2');
      recordingType = "laser";
      recording = true;
    }
  } else {
    println("ERROR: Serial not connected");
  }
}

public void openTextureScan(int theValue) {
  textureFilename = selectInput("Open texture .mov file...");
  
  if (textureFilename == null) {
    println("ERROR: No texture file was selected");
  } else {
    loadTextureScan();
  }
}

public void openLaserScan(int theValue) {
  laserFilename = selectInput("Open laser .mov file...");
  
  if (laserFilename == null) {
    println("ERROR: No laser file was selected");
  } else {
    loadLaserScan();
  }
}

public void textureScan(int theValue) {
  if (serialConnected) {
    textureFilename = selectOutput("Save texture .mov to...");
    if (textureFilename == null) {
      println("ERROR: No texture output file was selected");
    } else {
      movie = new MovieMaker(this, videoWidth, videoHeight, textureFilename, framerate, MovieMaker.VIDEO, MovieMaker.LOSSLESS);
      command_start_time = millis();
      serial.write('2');
      recording = true;
      recordingType = "texture";
    }
  } else {
    println("ERROR: Serial not connected");
  }
}

public void serialConnect() {
  serial = new Serial(this, serialPort, 9600);
  serial.bufferUntil('\n');
  serialConnected = true;
}

public void camConnect() {
  cam = new Capture(this, videoWidth, videoHeight, camPort, framerate);
  camConnected = true;
}

public void processScans() {
  plyFilename = selectOutput("Save scan .ply to..."); 
//  plyFilename = "data/gnome.ply";
  if (plyFilename == null) {
    println("ERROR: No ply output file was selected");
  } else {
    processing = true;
    camConnected = false;
    println("Processing " + laserMovie.getFrameCount() + " frames...");
  }
}

public void testSpin() {
  if (serialConnected && !recording) {
    command_start_time = millis();
    serial.write('2');
  }
}

public void processScanFrame() {
  // code based on http://www.sjbaker.org/wiki/index.php?title=A_Simple_3D_Scanner
  
//  println("Processing frame: " + frame + "/" + laserMovie.getFrameCount());
  laserMovie.gotoFrameNumber(frame);
  laserMovie.read();
  laserImage = laserMovie.get();

  textureMovie.gotoFrameNumber(frame);
  textureMovie.read();
  textureImage = textureMovie.get();

  int brightestX = 0;
  float brightestValue = 0;
  
  laserImage.loadPixels();
  textureImage.loadPixels();
  
  int index = 0;
  
  float frameAngle = float(frame) * (360.0 / float(laserMovie.getFrameCount()));
  
  for (int y = 0; y < videoHeight; y++) {
    // find the brightest pixel
    brightestValue = 0;
    brightestX = -1;
    
    for (int x = 0; x < videoWidth; x++) {
      int pixelValue = laserImage.pixels[index];      
      float pixelBrightness = pixelValue >> 16 & 0xFF;
      
      if (pixelBrightness > brightestValue && pixelBrightness > threshold) {
        brightestValue = pixelBrightness;
        brightestX = x;
      }
      
      index++;
    }
    
    int[] thisColor = new int[3];
    float[] thisPoint = new float[3];
    float[] thisNormal = new float[3];
    
    if (brightestX > 0) {
      laserImage.pixels[y*videoWidth+brightestX] = color(0, 255, 0);
      float r = red(textureImage.pixels[y*videoWidth+brightestX]);
      float g = green(textureImage.pixels[y*videoWidth+brightestX]);
      float b = blue(textureImage.pixels[y*videoWidth+brightestX]);
      thisColor[0] = int(r);
      thisColor[1] = int(g);
      thisColor[2] = int(b);
      colorList.add(thisColor);

      float radius;
      float camAngle = camHFOV * (0.5 - float(brightestX) / float(videoWidth));
    
      float pointAngle = 180.0 - camAngle + laserOffset;
      radius = camDistance * sin(camAngle * degreesToRadians) / sin(pointAngle * degreesToRadians);
    
      float pointX = radius * sin(frameAngle * degreesToRadians);
      float pointY = radius * cos(frameAngle * degreesToRadians);
      float pointZ = -atan((camVFOV * degreesToRadians / 2.0)) * 2.0 * camDistance * float(y) / float(videoHeight);
    
      // println("line: " + y + " point: " + pointX + "," + pointY + "," + pointZ);
      // println("brightestX: " + brightestX + " camAngle: " + camAngle + " radius: " + radius);
      
      thisPoint[0] = pointX;
      thisPoint[1] = pointY;
      thisPoint[2] = pointZ;
      // println(thisPoint);
      pointList.add(thisPoint);

      // assume normals are all pointing outwards from 0,0,z = pointX,pointY,0 (should be point to camera...)
      // normalize it
      // float normalLength = sqrt((pointX * pointX) + (pointY * pointY) + (0.0 * 0.0));
      // thisNormal[0] = pointX/normalLength;
      // thisNormal[1] = pointY/normalLength;
      thisNormal[0] = pointX;
      thisNormal[1] = pointY;
      thisNormal[2] = 0.0;
      normalList.add(thisNormal);

      p.addPoint(thisPoint[0], -thisPoint[2], -thisPoint[1], r/255.0, g/255.0, b/255.0, 1);
    }
  }

  laserImage.updatePixels();
}

