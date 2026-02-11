// Engine_Ygg.sc
// Norns engine for Ygg drone synthesizer
// MPE-capable Lyra-8 inspired synthesis
//
// NOTE: The SynthDefs in this file are duplicated from ygg_synths.scd
// This is intentional - Norns engines must be self-contained single files.
// When modifying SynthDefs, update both files to keep them in sync.

Engine_Ygg : CroneEngine
{
  var <voices;
  var <voiceBuses;
  var <modBuses;
  var <lfoBus;
  var <delayBus;
  var <driveBus;
  
  var <voiceMixer;
  var <crossMod;
  var <lfo;
  var <delay;
  var <drive;
  
  var <voiceIdx;
  var <activeNotes;
  
  var <hold;
  var <vibratoDepth;
  var <routing;
  
  *new
  {
    arg context, doneCallback;
    ^super.new(context, doneCallback);
  }
  
  alloc
  {
    // Allocate buses
    voiceBuses = 8.collect { Bus.audio(context.server, 2) };
    modBuses = 8.collect { Bus.audio(context.server, 1) };
    lfoBus = Bus.audio(context.server, 1);
    delayBus = Bus.audio(context.server, 2);
    driveBus = Bus.audio(context.server, 2);
    
    // Initialize voice tracking
    voices = Array.newClear(8);
    voiceIdx = 1;
    activeNotes = Dictionary.new;
    
    // Global state
    hold = 0.0;
    vibratoDepth = 0.01;
    routing = 0;
    
    // Load SynthDefs
    this.addSynthDefs;
    
    context.server.sync;
    
    // Create synth chain
    this.createSynthChain;
    
    // Add commands
    this.addCommands;
  }
  
  addSynthDefs
  {
    // ================================================================
    // Global LFO
    // ================================================================
    SynthDef(\yggLFO,
    {
      arg out=0, freqA=0.1, freqB=0.2, style=0;
      var lfo, oscA, oscB;
      
      oscA = SinOsc.ar(freqA);
      oscB = SinOsc.ar(freqB);
      
      // LFO modes - use SelectX for audio-rate selection with interpolation
      lfo = SelectX.ar(
        style.clip(0, 3),
        [
          oscA,
          (oscA + oscB) * 0.5,
          oscA * oscB,
          SinOsc.ar(freqA + (oscB * freqB * 2))
        ]
      );
      
      Out.ar(out, lfo);
    }).add;
    
    // ================================================================
    // Voice
    // ================================================================
    SynthDef(\yggVoice,
    {
      arg out=0, voiceNum=0, freq=440, amp=0.5, gate=1,
          attack=0.1, release=1.0, hold=0.0,
          vibratoFreq=5.0, vibratoDepth=0.01,
          harmonics=0.0, pitchBend=0.0, pressure=1.0,
          modDepth=0.0, modBus=0, lfoBus=0, pressureThreshold=0.1;
      
      var sig, leftSig, rightSig;
      var env, currentAmp;
      var modSig, finalFreq;
      var sine, square, saw, morphedSig;
      var vibratoL, vibratoR;
      
      finalFreq = freq * pitchBend.midiratio;
      modSig = In.ar(modBus, 1);
      finalFreq = finalFreq + (modSig * modDepth * finalFreq * 0.5);
      
      // Envelope with proper attack/release
      env = EnvGen.ar(
        Env.asr(attack, 1.0, release),
        gate,
        doneAction: 2
      );
      
      // Apply hold: during release (gate=0), don't go below hold level
      // Scale amplitude by 0.5 per voice to leave headroom for 8 voices
      currentAmp = env.max(hold * (1 - gate)) * amp * 0.5 * pressure.linlin(0, 1, 0.5, 1.0);
      
      sine = SinOsc.ar(finalFreq);
      square = Pulse.ar(finalFreq, 0.5);
      saw = LFSaw.ar(finalFreq);
      
      // Morph between waveforms: 0-0.5 blends sine->square, 0.5-1.0 blends square->saw
      morphedSig = LinXFade2.ar(
        XFade2.ar(sine, square, harmonics.linlin(0, 0.5, -1, 1)),
        XFade2.ar(square, saw, harmonics.linlin(0.5, 1.0, -1, 1)),
        harmonics.linlin(0, 1, -1, 1)
      );
      
      sig = morphedSig * currentAmp;
      
      vibratoL = SinOsc.ar(vibratoFreq, 0);
      vibratoR = SinOsc.ar(vibratoFreq, pi * 0.5);
      
      // Always use delay for stereo spread, depth controls amount
      leftSig = DelayC.ar(sig, 0.1, 
        (vibratoL * vibratoDepth / finalFreq).abs.clip(0.0001, 0.05)
      );
      
      rightSig = DelayC.ar(sig, 0.1, 
        (vibratoR * vibratoDepth / finalFreq).abs.clip(0.0001, 0.05)
      );
      
      leftSig = (leftSig * 2).softclip * 0.5;
      rightSig = (rightSig * 2).softclip * 0.5;
      
      Out.ar(out, [leftSig, rightSig]);
    }).add;
    
    // ================================================================
    // Voice Mixer
    // ================================================================
    SynthDef(\yggVoiceMixer,
    {
      arg out=0,
          voice1Bus=0, voice2Bus=0, voice3Bus=0, voice4Bus=0,
          voice5Bus=0, voice6Bus=0, voice7Bus=0, voice8Bus=0;
      
      var mix;
      
      // Sum all voice buses (stereo) and scale by 1/8 to prevent clipping
      mix = (In.ar(voice1Bus, 2) +
            In.ar(voice2Bus, 2) +
            In.ar(voice3Bus, 2) +
            In.ar(voice4Bus, 2) +
            In.ar(voice5Bus, 2) +
            In.ar(voice6Bus, 2) +
            In.ar(voice7Bus, 2) +
            In.ar(voice8Bus, 2)) * 0.125;  // 1/8 = 0.125
      
      Out.ar(out, mix);
    }).add;
    
    // ================================================================
    // Cross-Modulation
    // ================================================================
    SynthDef(\yggCrossMod,
    {
      arg voice1Bus=0, voice2Bus=0, voice3Bus=0, voice4Bus=0,
          voice5Bus=0, voice6Bus=0, voice7Bus=0, voice8Bus=0,
          out1=0, out2=0, out3=0, out4=0,
          out5=0, out6=0, out7=0, out8=0, routing=0;
      
      var v1, v2, v3, v4, v5, v6, v7, v8;
      var pair1, pair2, pair3, pair4;
      var mod12, mod34, mod56, mod78;
      
      v1 = In.ar(voice1Bus, 2).sum;
      v2 = In.ar(voice2Bus, 2).sum;
      v3 = In.ar(voice3Bus, 2).sum;
      v4 = In.ar(voice4Bus, 2).sum;
      v5 = In.ar(voice5Bus, 2).sum;
      v6 = In.ar(voice6Bus, 2).sum;
      v7 = In.ar(voice7Bus, 2).sum;
      v8 = In.ar(voice8Bus, 2).sum;
      
      pair1 = v1 + v2;
      pair2 = v3 + v4;
      pair3 = v5 + v6;
      pair4 = v7 + v8;
      
      4.do
      {
        #mod12, mod34, mod56, mod78 = Select.ar(K2A.ar(routing), [
          [pair2, pair1, pair4, pair3],
          [pair3, pair4, pair1, pair2],
          [pair4, pair1, pair2, pair3]
        ]);
        
        pair1 = (v1 + v2 + (mod12 * 0.2)).clip2(2).softclip;
        pair2 = (v3 + v4 + (mod34 * 0.2)).clip2(2).softclip;
        pair3 = (v5 + v6 + (mod56 * 0.2)).clip2(2).softclip;
        pair4 = (v7 + v8 + (mod78 * 0.2)).clip2(2).softclip;
      };
      
      Out.ar(out1, mod12);
      Out.ar(out2, mod12);
      Out.ar(out3, mod34);
      Out.ar(out4, mod34);
      Out.ar(out5, mod56);
      Out.ar(out6, mod56);
      Out.ar(out7, mod78);
      Out.ar(out8, mod78);
    }).add;
    
    // ================================================================
    // Delay
    // ================================================================
    SynthDef(\yggDelay,
    {
      arg in=0, out=0, delayTime1=0.25, delayTime2=0.5,
          delayMod1=0.1, delayMod2=0.15, delayFB=0.3,
          delayMix=0.3, lfoBus=0, modType=0;
      
      var input, delayed, lfo, modSig, time1, time2, fb, wet, dry;
      
      input = In.ar(in, 2);
      lfo = In.ar(lfoBus, 1);
      
      modSig = Select.kr(modType, [
        lfo,
        (lfo > 0).linlin(0, 1, -1, 1)
      ]);
      
      time1 = (delayTime1 + (modSig * delayMod1)).clip(0.001, 2.0);
      time2 = (delayTime2 + (modSig * delayMod2)).clip(0.001, 2.0);
      
      fb = LocalIn.ar(2);
      delayed = DelayC.ar(input + (fb * delayFB), 2.0, [time1, time2]);
      delayed = delayed.softclip;
      LocalOut.ar(delayed);
      
      wet = delayed;
      dry = input;
      
      Out.ar(out, XFade2.ar(dry, wet, delayMix * 2 - 1));
    }).add;
    
    // ================================================================
    // Drive
    // ================================================================
    SynthDef(\yggDrive,
    {
      arg in=0, out=0, distDrive=1.0, distMix=0.0;
      var input, driven, wet, dry;
      
      input = In.ar(in, 2);
      driven = (input * distDrive).tanh;
      driven = LeakDC.ar(driven);
      driven = (driven + (driven.squared * 0.2)).softclip;
      
      wet = driven * 0.7;
      dry = input;
      
      Out.ar(out, XFade2.ar(dry, wet, distMix * 2 - 1));
    }).add;
  }
  
  createSynthChain
  {
    drive = Synth(\yggDrive, [
      \in, driveBus,  // FIXED: was delayBus
      \out, context.out_b,
      \distDrive, 1.0,
      \distMix, 0.0
    ], target: context.xg, addAction: \addToTail);
    
    delay = Synth(\yggDelay, [
      \in, delayBus,
      \out, driveBus,
      \delayTime1, 0.25,
      \delayTime2, 0.5,
      \delayFB, 0.3,
      \delayMix, 0.3,
      \lfoBus, lfoBus,
      \modType, 0
    ], target: context.xg, addAction: \addToHead);
    
    voiceMixer = Synth(\yggVoiceMixer, [
      \out, delayBus,
      \voice1Bus, voiceBuses[0],
      \voice2Bus, voiceBuses[1],
      \voice3Bus, voiceBuses[2],
      \voice4Bus, voiceBuses[3],
      \voice5Bus, voiceBuses[4],
      \voice6Bus, voiceBuses[5],
      \voice7Bus, voiceBuses[6],
      \voice8Bus, voiceBuses[7]
    ], target: context.xg, addAction: \addToHead);
    
    lfo = Synth(\yggLFO, [
      \out, lfoBus,
      \freqA, 0.1,
      \freqB, 0.2,
      \style, 0
    ], target: context.xg, addAction: \addToHead);
    
    crossMod = Synth(\yggCrossMod, [
      \voice1Bus, voiceBuses[0],
      \voice2Bus, voiceBuses[1],
      \voice3Bus, voiceBuses[2],
      \voice4Bus, voiceBuses[3],
      \voice5Bus, voiceBuses[4],
      \voice6Bus, voiceBuses[5],
      \voice7Bus, voiceBuses[6],
      \voice8Bus, voiceBuses[7],
      \out1, modBuses[0],
      \out2, modBuses[1],
      \out3, modBuses[2],
      \out4, modBuses[3],
      \out5, modBuses[4],
      \out6, modBuses[5],
      \out7, modBuses[6],
      \out8, modBuses[7],
      \routing, routing
    ], target: context.xg, addAction: \addToHead);
  }
  
  addCommands
  {
    // Note on/off
    this.addCommand(\noteOn, "if", { arg msg;
      var note = msg[1].asInteger;
      var vel = msg[2];
      this.noteOn(note, vel);
    });
    
    this.addCommand(\noteOff, "i", { arg msg;
      var note = msg[1].asInteger;
      this.noteOff(note);
    });
    
    // MPE
    this.addCommand(\pitchBend, "if", { arg msg;
      var note = msg[1].asInteger;
      var bend = msg[2];
      this.setPitchBend(note, bend);
    });
    
    this.addCommand(\pressure, "if", { arg msg;
      var note = msg[1].asInteger;
      var pressure = msg[2];
      this.setPressure(note, pressure);
    });
    
    // Voice parameters
    this.addCommand(\voiceAttack, "if", { arg msg;
      var voice = msg[1].asInteger;
      this.setVoiceParam(voice, \attack, msg[2]);
    });
    
    this.addCommand(\voiceRelease, "if", { arg msg;
      var voice = msg[1].asInteger;
      this.setVoiceParam(voice, \release, msg[2]);
    });
    
    this.addCommand(\voiceVibratoFreq, "if", { arg msg;
      var voice = msg[1].asInteger;
      this.setVoiceParam(voice, \vibratoFreq, msg[2]);
    });
    
    this.addCommand(\voiceHarmonics, "if", { arg msg;
      var voice = msg[1].asInteger;
      this.setVoiceParam(voice, \harmonics, msg[2]);
    });
    
    this.addCommand(\voiceModDepth, "if", { arg msg;
      var voice = msg[1].asInteger;
      this.setVoiceParam(voice, \modDepth, msg[2]);
    });
    
    // Global parameters
    this.addCommand(\hold, "f", { arg msg;
      this.setHold(msg[1]);
    });
    
    this.addCommand(\vibratoDepth, "f", { arg msg;
      this.setVibratoDepth(msg[1]);
    });
    
    this.addCommand(\routing, "i", { arg msg;
      this.setRouting(msg[1]);
    });
    
    // LFO
    this.addCommand(\lfoFreqA, "f", { arg msg;
      lfo.set(\freqA, msg[1]);
    });
    
    this.addCommand(\lfoFreqB, "f", { arg msg;
      lfo.set(\freqB, msg[1]);
    });
    
    this.addCommand(\lfoStyle, "i", { arg msg;
      lfo.set(\style, msg[1]);
    });
    
    // Delay
    this.addCommand(\delayTime1, "f", { arg msg;
      delay.set(\delayTime1, msg[1]);
    });
    
    this.addCommand(\delayTime2, "f", { arg msg;
      delay.set(\delayTime2, msg[1]);
    });
    
    this.addCommand(\delayMod1, "f", { arg msg;
      delay.set(\delayMod1, msg[1]);
    });
    
    this.addCommand(\delayMod2, "f", { arg msg;
      delay.set(\delayMod2, msg[1]);
    });
    
    this.addCommand(\delayFB, "f", { arg msg;
      delay.set(\delayFB, msg[1]);
    });
    
    this.addCommand(\delayMix, "f", { arg msg;
      delay.set(\delayMix, msg[1]);
    });
    
    this.addCommand(\delayModType, "i", { arg msg;
      delay.set(\modType, msg[1]);
    });
    
    // Drive
    this.addCommand(\distDrive, "f", { arg msg;
      drive.set(\distDrive, msg[1]);
    });
    
    this.addCommand(\distMix, "f", { arg msg;
      drive.set(\distMix, msg[1]);
    });
  }
  
  noteOn
  {
    arg note, vel=1.0;
    var voiceNum, freq, amp, existingVoice;
    
    freq = note.midicps;
    amp = vel;
    
    existingVoice = activeNotes[note];
    
    if(existingVoice.notNil and: { voices[existingVoice].notNil and: { voices[existingVoice].isPlaying } })
    {
      voiceNum = existingVoice;
      voices[voiceNum].set(\gate, 1, \freq, freq, \amp, amp);
    }
    {
      voiceNum = voiceIdx - 1;
      voiceIdx = (voiceIdx % 8) + 1;
      
      if(voices[voiceNum].notNil)
      {
        activeNotes.keysValuesDo
        {
          arg key, val;
          if(val == voiceNum) { activeNotes.removeAt(key); };
        };
        
        if(voices[voiceNum].isPlaying)
        {
          // Smooth crossfade: quick release on stolen voice
          voices[voiceNum].set(\release, 0.05, \gate, 0);
        };
      };
      
      voices[voiceNum] = Synth(\yggVoice, [
        \out, voiceBuses[voiceNum],
        \voiceNum, voiceNum,
        \freq, freq,
        \amp, amp,
        \gate, 1,
        \attack, 0.05,  // Short attack for smooth voice stealing
        \release, 1.0,
        \hold, hold,
        \vibratoFreq, 5.0,
        \vibratoDepth, vibratoDepth,
        \harmonics, 0.0,
        \pitchBend, 0.0,
        \pressure, 1.0,
        \modDepth, 0.0,
        \modBus, modBuses[voiceNum],
        \lfoBus, lfoBus
      ], target: context.xg, addAction: \addToHead);
    };
    
    activeNotes[note] = voiceNum;
  }
  
  noteOff
  {
    arg note;
    var voiceNum = activeNotes[note];
    
    if(voiceNum.notNil && voices[voiceNum].notNil && voices[voiceNum].isPlaying)
    {
      voices[voiceNum].set(\gate, 0);
      // Keep note mapping for potential reuse
    };
  }
  
  setPitchBend
  {
    arg note, bendSemitones;
    var voiceNum = activeNotes[note];
    
    if(voiceNum.notNil && voices[voiceNum].notNil)
    {
      voices[voiceNum].set(\pitchBend, bendSemitones);
    };
  }
  
  setPressure
  {
    arg note, pressure;
    var voiceNum = activeNotes[note];
    
    if(voiceNum.notNil && voices[voiceNum].notNil)
    {
      voices[voiceNum].set(\pressure, pressure);
    };
  }
  
  setVoiceParam
  {
    arg voiceNum, param, value;
    
    if(voices[voiceNum].notNil)
    {
      voices[voiceNum].set(param, value);
    };
  }
  
  setHold
  {
    arg value;
    hold = value.clip(0, 1);
    8.do
    {
      arg i;
      if(voices[i].notNil)
      {
        voices[i].set(\hold, hold);
      };
    };
  }
  
  setVibratoDepth
  {
    arg value;
    vibratoDepth = value;
    8.do
    {
      arg i;
      if(voices[i].notNil)
      {
        voices[i].set(\vibratoDepth, vibratoDepth);
      };
    };
  }
  
  setRouting
  {
    arg value;
    routing = value.clip(0, 2);
    crossMod.set(\routing, routing);
  }
  
  free
  {
    voices.do { arg v; if(v.notNil) { v.free } };
    voiceMixer.free;
    crossMod.free;
    lfo.free;
    delay.free;
    drive.free;
    
    voiceBuses.do { arg b; b.free };
    modBuses.do { arg b; b.free };
    lfoBus.free;
    delayBus.free;
    driveBus.free;
  }
}
