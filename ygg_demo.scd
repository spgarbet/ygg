// Ygg Engine Manager and Demo Script
// Manages voice allocation, MPE, and global parameters

(
// ====================================================================
// YGG ENGINE MANAGER CLASS
// ====================================================================
~ygg = (
  // Audio buses
  voiceBuses: nil,
  modBuses: nil,
  lfoBus: nil,
  delayBus: nil,
  driveBus: nil,
  
  // Synth nodes
  voices: nil,
  crossMod: nil,
  lfo: nil,
  delay: nil,
  drive: nil,
  
  // Voice allocation
  voiceIdx: 1,  // ring buffer index for voice stealing
  activeNotes: nil,  // dict of midi note -> voice index
  
  // Global parameters
  hold: 0.0,
  vibratoDepth: 0.01,
  routing: 0,  // 0=neighbor, 1=cross, 2=loop
  
  // ================================================================
  // INITIALIZATION
  // ================================================================
  init: {
    arg self;
    
    s.waitForBoot
    {
      // Allocate buses
      self.voiceBuses = 8.collect { Bus.audio(s, 2) };
      self.modBuses = 8.collect { Bus.audio(s, 1) };
      self.lfoBus = Bus.audio(s, 1);
      self.delayBus = Bus.audio(s, 2);
      self.driveBus = Bus.audio(s, 2);
      
      // Initialize voice tracking
      self.voices = Array.newClear(8);
      self.activeNotes = Dictionary.new;
      
      // Wait for SynthDefs to load
      s.sync;
      
      // Create synth chain in reverse order
      self.drive = Synth(\yggDrive, [
        \in, self.delayBus,
        \out, 0,
        \distDrive, 1.0,
        \distMix, 0.0
      ], addAction: \addToTail);
      
      self.delay = Synth(\yggDelay, [
        \in, self.delayBus,
        \out, self.driveBus,
        \delayTime1, 0.25,
        \delayTime2, 0.5,
        \delayFB, 0.3,
        \delayMix, 0.3,
        \lfoBus, self.lfoBus,
        \modType, 0
      ], addAction: \addToHead);
      
      self.lfo = Synth(\yggLFO, [
        \out, self.lfoBus,
        \freqA, 0.1,
        \freqB, 0.2,
        \style, 0
      ], addAction: \addToHead);
      
      self.crossMod = Synth(\yggCrossMod, [
        \voice1Bus, self.voiceBuses[0],
        \voice2Bus, self.voiceBuses[1],
        \voice3Bus, self.voiceBuses[2],
        \voice4Bus, self.voiceBuses[3],
        \voice5Bus, self.voiceBuses[4],
        \voice6Bus, self.voiceBuses[5],
        \voice7Bus, self.voiceBuses[6],
        \voice8Bus, self.voiceBuses[7],
        \out1, self.modBuses[0],
        \out2, self.modBuses[1],
        \out3, self.modBuses[2],
        \out4, self.modBuses[3],
        \out5, self.modBuses[4],
        \out6, self.modBuses[5],
        \out7, self.modBuses[6],
        \out8, self.modBuses[7],
        \routing, self.routing
      ], addAction: \addToHead);
      
      "Ygg Engine initialized.".postln;
    };
  },
  
  // ================================================================
  // NOTE ON - with voice stealing
  // ================================================================
  noteOn: {
    arg self, note, vel=127;
    var voiceNum, freq, amp;
    
    freq = note.midicps;
    amp = vel.linlin(0, 127, 0, 1);
    
    // Check if note already playing
    if(self.activeNotes[note].notNil)
    {
      voiceNum = self.activeNotes[note];
      // Re-trigger existing voice
      self.voices[voiceNum].set(\gate, 0);
      self.voices[voiceNum].free;
    }
    {
      // Steal oldest voice (ring buffer)
      voiceNum = self.voiceIdx - 1;  // convert to 0-indexed
      self.voiceIdx = (self.voiceIdx % 8) + 1;
      
      // Free old voice if exists
      if(self.voices[voiceNum].notNil)
      {
        self.voices[voiceNum].set(\gate, 0);
        self.voices[voiceNum].free;
      };
    };
    
    // Create new voice
    self.voices[voiceNum] = Synth(\yggVoice, [
      \out, self.voiceBuses[voiceNum],
      \voiceNum, voiceNum,
      \freq, freq,
      \amp, amp,
      \gate, 1,
      \attack, 0.1,
      \release, 1.0,
      \hold, self.hold,
      \vibratoFreq, 5.0,
      \vibratoDepth, self.vibratoDepth,
      \harmonics, 0.0,
      \pitchBend, 0.0,
      \pressure, 1.0,
      \modDepth, 0.0,
      \modBus, self.modBuses[voiceNum],
      \lfoBus, self.lfoBus
    ], addAction: \addToHead);
    
    self.activeNotes[note] = voiceNum;
    
    ("Note On: " ++ note ++ " -> Voice " ++ voiceNum).postln;
  },
  
  // ================================================================
  // NOTE OFF
  // ================================================================
  noteOff: {
    arg self, note;
    var voiceNum;
    
    voiceNum = self.activeNotes[note];
    
    if(voiceNum.notNil)
    {
      if(self.voices[voiceNum].notNil)
      {
        self.voices[voiceNum].set(\gate, 0);
        ("Note Off: " ++ note ++ " (Voice " ++ voiceNum ++ ")").postln;
      };
      
      self.activeNotes.removeAt(note);
    };
  },
  
  // ================================================================
  // MPE CONTROLS
  // ================================================================
  setPitchBend: {
    arg self, note, bendSemitones;
    var voiceNum = self.activeNotes[note];
    
    if(voiceNum.notNil)
    {
      self.voices[voiceNum].set(\pitchBend, bendSemitones);
    };
  },
  
  setPressure: {
    arg self, note, pressure;  // 0-1
    var voiceNum = self.activeNotes[note];
    
    if(voiceNum.notNil)
    {
      self.voices[voiceNum].set(\pressure, pressure);
    };
  },
  
  // ================================================================
  // VOICE PARAMETER CONTROLS
  // ================================================================
  setVoiceParam: {
    arg self, voiceNum, param, value;
    
    if(self.voices[voiceNum].notNil)
    {
      self.voices[voiceNum].set(param, value);
    };
  },
  
  setAllVoices: {
    arg self, param, value;
    
    8.do
    {
      arg i;
      if(self.voices[i].notNil)
      {
        self.voices[i].set(param, value);
      };
    };
  },
  
  // ================================================================
  // GLOBAL PARAMETER CONTROLS
  // ================================================================
  setHold: {
    arg self, value;  // 0-1
    self.hold = value.clip(0, 1);
    self.setAllVoices(\hold, self.hold);
  },
  
  setVibratoDepth: {
    arg self, value;
    self.vibratoDepth = value;
    self.setAllVoices(\vibratoDepth, self.vibratoDepth);
  },
  
  setRouting: {
    arg self, value;  // 0=neighbor, 1=cross, 2=loop
    self.routing = value.clip(0, 2);
    self.crossMod.set(\routing, self.routing);
  },
  
  setLFO: {
    arg self, freqA, freqB, style;
    self.lfo.set(\freqA, freqA, \freqB, freqB, \style, style);
  },
  
  setDelay: {
    arg self, time1, time2, mod1, mod2, fb, mix, modType;
    self.delay.set(
      \delayTime1, time1,
      \delayTime2, time2,
      \delayMod1, mod1,
      \delayMod2, mod2,
      \delayFB, fb,
      \delayMix, mix,
      \modType, modType
    );
  },
  
  setDrive: {
    arg self, drive, mix;
    self.drive.set(\distDrive, drive, \distMix, mix);
  },
  
  // ================================================================
  // CLEANUP
  // ================================================================
  free: {
    arg self;
    
    self.voices.do { arg v; if(v.notNil) { v.free } };
    self.crossMod.free;
    self.lfo.free;
    self.delay.free;
    self.drive.free;
    
    self.voiceBuses.do { arg b; b.free };
    self.modBuses.do { arg b; b.free };
    self.lfoBus.free;
    self.delayBus.free;
    self.driveBus.free;
    
    "Ygg Engine freed.".postln;
  }
);

// Initialize the engine
~ygg.init;
)

// ====================================================================
// DEMO SCRIPT
// ====================================================================
(
// Wait for engine to initialize
1.wait;

// Demo sequence
fork
{
  "=== YGG ENGINE DEMO ===".postln;
  "".postln;
  
  // ================================================================
  // 1. Basic drone with held notes
  // ================================================================
  "1. Creating evolving drone with hold...".postln;
  ~ygg.setHold(0.3);  // hold at 30% volume
  ~ygg.setAllVoices(\attack, 0.5);
  ~ygg.setAllVoices(\release, 3.0);
  ~ygg.setAllVoices(\vibratoFreq, 6.0);
  ~ygg.setVibratoDepth(0.02);
  
  // Play a cluster
  [60, 64, 67, 71].do
  {
    arg note;
    ~ygg.noteOn(note, 100);
    0.1.wait;
  };
  
  4.wait;
  
  // ================================================================
  // 2. Add harmonics morphing
  // ================================================================
  "2. Morphing harmonics (sine -> square -> saw)...".postln;
  10.do
  {
    arg i;
    ~ygg.setAllVoices(\harmonics, i.linlin(0, 9, 0, 1));
    0.4.wait;
  };
  
  2.wait;
  
  // ================================================================
  // 3. Cross-modulation routing changes
  // ================================================================
  "3. Changing cross-modulation routing...".postln;
  ~ygg.setAllVoices(\modDepth, 200);
  
  ~ygg.setRouting(0);  // neighbor
  "Routing: neighbor".postln;
  3.wait;
  
  ~ygg.setRouting(1);  // cross
  "Routing: cross".postln;
  3.wait;
  
  ~ygg.setRouting(2);  // loop
  "Routing: loop".postln;
  3.wait;
  
  // ================================================================
  // 4. LFO modulation of delay
  // ================================================================
  "4. Adding modulated delay...".postln;
  ~ygg.setLFO(0.2, 0.3, 1);  // sum mode
  ~ygg.setDelay(0.25, 0.5, 0.1, 0.15, 0.4, 0.5, 0);
  
  4.wait;
  
  // ================================================================
  // 5. Tube distortion
  // ================================================================
  "5. Adding tube distortion...".postln;
  ~ygg.setDrive(3.0, 0.6);
  
  4.wait;
  
  // ================================================================
  // 6. MPE-style pitch bend and pressure
  // ================================================================
  "6. Simulating MPE pitch bend and pressure...".postln;
  20.do
  {
    arg i;
    var bend = sin(i * 0.3) * 2;  // ±2 semitones
    var pressure = i.linlin(0, 19, 0.5, 1.0);
    
    ~ygg.setPitchBend(60, bend);
    ~ygg.setPressure(60, pressure);
    0.2.wait;
  };
  
  2.wait;
  
  // ================================================================
  // 7. Release all notes
  // ================================================================
  "7. Releasing notes...".postln;
  ~ygg.setHold(0.0);  // full release
  [60, 64, 67, 71].do
  {
    arg note;
    ~ygg.noteOff(note);
    0.5.wait;
  };
  
  4.wait;
  
  // ================================================================
  // 8. Final spectral harmony demonstration
  // ================================================================
  "8. Final spectral harmony...".postln;
  ~ygg.setHold(0.4);
  ~ygg.setAllVoices(\harmonics, 0.7);
  ~ygg.setVibratoDepth(0.03);
  
  // Spectral chord: fundamental + partials
  [48, 60, 67, 72, 76, 79, 82].do
  {
    arg note, i;
    ~ygg.noteOn(note, 80 - (i * 5));
    0.15.wait;
  };
  
  8.wait;
  
  // Fade out
  "Fading out...".postln;
  10.do
  {
    arg i;
    ~ygg.setDrive(3.0, 0.6 - (i * 0.06));
    0.5.wait;
  };
  
  [48, 60, 67, 72, 76, 79, 82].do
  {
    arg note;
    ~ygg.noteOff(note);
  };
  
  4.wait;
  
  "=== DEMO COMPLETE ===".postln;
};
)

// ====================================================================
// INTERACTIVE TESTING
// ====================================================================

// Play a note
~ygg.noteOn(60, 100);

// Release a note
~ygg.noteOff(60);

// Set hold level (0-1)
~ygg.setHold(0.5);

// Set vibrato depth
~ygg.setVibratoDepth(0.05);

// Change cross-modulation routing (0=neighbor, 1=cross, 2=loop)
~ygg.setRouting(1);

// Set LFO (freqA, freqB, style: 0=single, 1=sum, 2=product, 3=fm)
~ygg.setLFO(0.1, 0.2, 1);

// Set delay (time1, time2, mod1, mod2, feedback, mix, modType: 0=smooth, 1=jump)
~ygg.setDelay(0.25, 0.5, 0.1, 0.15, 0.4, 0.5, 0);

// Set distortion (drive, mix)
~ygg.setDrive(2.0, 0.5);

// Set individual voice parameters
~ygg.setVoiceParam(0, \harmonics, 0.8);
~ygg.setVoiceParam(0, \vibratoFreq, 7.0);

// Set all voices
~ygg.setAllVoices(\attack, 0.3);
~ygg.setAllVoices(\release, 2.0);

// MPE controls
~ygg.setPitchBend(60, 2.0);  // +2 semitones
~ygg.setPressure(60, 0.8);   // 80% pressure

// Cleanup
~ygg.free;
