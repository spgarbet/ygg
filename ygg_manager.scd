// ygg_manager.scd
// Manager class for Ygg drone synthesizer
// Requires: ygg_synths.scd to be loaded first

(
// Load SynthDefs if not already loaded
if(SynthDescLib.global[\yggVoice].isNil)
{
  "Loading Ygg SynthDefs...".postln;
  thisProcess.nowExecutingPath.dirname +/+ "ygg_synths.scd".load;
  s.sync;
};

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
  voiceMixer: nil,  // new: sums voices to delay input
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
  defaultAttack: 0.1,
  defaultRelease: 1.0,
  
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
      
      // Create synth chain with proper ordering
      // Order: Voices(head) -> CrossMod -> VoiceMixer -> Delay -> Drive(tail)
      
      self.drive = Synth(\yggDrive, [
        \in, self.driveBus,
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
      ], addAction: \addBefore, target: self.drive);
      
      // Voice mixer - sums all voices to delay input
      self.voiceMixer = Synth(\yggVoiceMixer, [
        \out, self.delayBus,
        \voice1Bus, self.voiceBuses[0],
        \voice2Bus, self.voiceBuses[1],
        \voice3Bus, self.voiceBuses[2],
        \voice4Bus, self.voiceBuses[3],
        \voice5Bus, self.voiceBuses[4],
        \voice6Bus, self.voiceBuses[5],
        \voice7Bus, self.voiceBuses[6],
        \voice8Bus, self.voiceBuses[7]
      ], addAction: \addBefore, target: self.delay);
      
      self.lfo = Synth(\yggLFO, [
        \out, self.lfoBus,
        \freqA, 0.1,
        \freqB, 0.2,
        \style, 0
      ], addAction: \addToHead);  // LFO can be anywhere, uses its own bus
      
      // PRE-ALLOCATE ALL 8 VOICES - they stay alive forever (at HEAD)
      "Creating 8 persistent voices...".postln;
      8.do { |i|
        self.voices[i] = Synth(\yggVoice, [
          \out, self.voiceBuses[i],
          \voiceNum, i,
          \freq, 440,
          \amp, 0.5,
          \pressure, 0.0,  // Start silent
          \attack, self.defaultAttack,
          \release, self.defaultRelease,
          \hold, self.hold,
          \vibratoFreq, 5.0,
          \vibratoDepth, self.vibratoDepth,
          \harmonics, 0.0,
          \pitchBend, 0.0,
          \modDepth, 0.0,
          \modBus, self.modBuses[i],
          \lfoBus, self.lfoBus
        ], addAction: \addToHead);
      };
      
      // CrossMod AFTER voices (reads voice buses, writes mod buses)
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
      ], addAction: \addAfter, target: self.voices[7]);  // After last voice
      
      "Ygg Engine initialized with 8 persistent voices.".postln;
    };
  },
  
  // ================================================================
  // NOTE ON - voice stealing with pre-allocated voices
  // ================================================================
  noteOn: {
    arg self, note, vel=127;
    var voiceNum, freq, amp, existingVoice;
    
    freq = note.midicps;
    amp = vel.linlin(0, 127, 0, 1);
    
    // Check if this note is already assigned to a voice
    existingVoice = self.activeNotes[note];
    
    if(existingVoice.notNil)
    {
      // Note already playing - just update it
      voiceNum = existingVoice;
      ("Note On (update): " ++ note ++ " -> Voice " ++ voiceNum).postln;
    }
    {
      // Steal the next voice in round-robin
      voiceNum = self.voiceIdx - 1;  // Convert to 0-indexed
      self.voiceIdx = (self.voiceIdx % 8) + 1;
      
      // Remove old note mapping if this voice was playing something
      self.activeNotes.keysValuesDo { |oldNote, oldVoice|
        if(oldVoice == voiceNum) {
          self.activeNotes.removeAt(oldNote);
        };
      };
      
      ("Note On (steal): " ++ note ++ " -> Voice " ++ voiceNum).postln;
    };
    
    // Configure the voice (it already exists, just set parameters)
    self.voices[voiceNum].set(
      \freq, freq,
      \amp, amp,
      \pressure, 1.0  // Turn on
    );
    
    self.activeNotes[note] = voiceNum;
  },
  
  // ================================================================
  // NOTE OFF - releases pressure
  // ================================================================
  noteOff: {
    arg self, note;
    var voiceNum;
    
    voiceNum = self.activeNotes[note];
    
    if(voiceNum.notNil)
    {
      // Set pressure to 0 - voice will release toward hold level
      self.voices[voiceNum].set(\pressure, 0.0);
      ("Note Off: " ++ note ++ " (Voice " ++ voiceNum ++ " -> release)").postln;
      
      // NOTE: We intentionally keep the note in activeNotes
      // This allows noteOn to find and reuse this voice while it's still sounding
      // The mapping is only removed when the voice is actually stolen for a new note
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
    
    if(voiceNum.notNil and: { self.voices[voiceNum].notNil and: { self.voices[voiceNum].isPlaying } })
    {
      // Pressure can drive amplitude below hold, enabling organic fades
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
    
    if(self.voices.isNil)
    {
      "Warning: setAllVoices called before engine initialized".postln;
      ^this;
    };
    
    // Also update defaults for future voices
    if(param == \attack) { self.defaultAttack = value };
    if(param == \release) { self.defaultRelease = value };
    
    // Update all voices (they're pre-allocated so always exist)
    8.do { |i|
      self.voices[i].set(param, value);
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
    
    // Immediately free all synths
    self.voices.do { arg v; if(v.notNil) { v.free } };
    if(self.voiceMixer.notNil) { self.voiceMixer.free };
    if(self.crossMod.notNil) { self.crossMod.free };
    if(self.lfo.notNil) { self.lfo.free };
    if(self.delay.notNil) { self.delay.free };
    if(self.drive.notNil) { self.drive.free };
    
    self.voiceBuses.do { arg b; b.free };
    self.modBuses.do { arg b; b.free };
    self.lfoBus.free;
    self.delayBus.free;
    self.driveBus.free;
    
    "Ygg Engine freed.".postln;
  }
);

"Ygg Manager loaded.".postln;
)
