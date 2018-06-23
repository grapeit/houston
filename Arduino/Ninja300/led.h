class Led
{
  char pin;
 
public:
  Led(char p) : pin(p) { pinMode(pin, OUTPUT); }
  void on() { digitalWrite(pin, HIGH); }
  void off() { digitalWrite(pin, LOW); }
  void pwm(unsigned char v) { analogWrite(pin, v); }
};

class RgbLed
{
  Led rl, gl, bl;
 
public:
  RgbLed(char r, char g, char b) : rl(r), gl(g), bl(b) { }
  
  void set(unsigned char r, unsigned char g, unsigned char b) {
    rl.pwm(r);
    gl.pwm(g);
    bl.pwm(b);
  }

  void set(unsigned long rgb) {
    rl.pwm((rgb >> 16) & 0xFF);
    gl.pwm((rgb >> 8) & 0xFF);
    bl.pwm(rgb & 0xFF);
  }

  enum Color {
    off    = 0x000000,
    white  = 0xFFFFFF,
    red    = 0xFF0000,
    green  = 0x00FF00,
    blue   = 0x0000FF,
    yellow = 0xAABB00
  };
};

