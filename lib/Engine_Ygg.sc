// Engine_Ygg.sc
// Ygg - 8-voice MPE drone synthesizer for Norns
// Lyra-8 inspired with ARH envelopes, cross-modulation, and morphing harmonics

Engine_Ygg : CroneEngine {
  // State variables
  var <voices;
  var <voiceGroup;
  var <voiceBuses;
  var <modBuses;
  var <lfoBus;
  var <delayBus;
  var <driveBus;
  var <lineOutBus;
  var <lineTap;
  var <voiceMixer;
  var <crossMod;
  var <lfo;
  var <delay;
  var <drive;
  var <voiceIdx = 1;
  var <activeNotes;
  var <hold = 0.0;
  var <vibratoDepth = 0.01;
  var <routing = 0;
  var <defaultAttack = 0.1;
  var <defaultRelease = 1.0;
  var <modType = 0;

  *new {
    arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    // Load SynthDefs
    this.loadSynthDefs;

    // Allocate buses
    voiceBuses = 8.collect { Bus.audio(context.server, 2) };
    modBuses = 8.collect { Bus.audio(context.server, 1) };
    lfoBus = Bus.audio(context.server, 1);
    delayBus = Bus.audio(context.server, 2);
    driveBus = Bus.audio(context.server, 2);
    lineOutBus = Bus.audio(context.server, 1);

    // Initialize voice tracking
    voices = Array.newClear(8);
    activeNotes = Dictionary.new;

    // Wait for server sync
    Server.default.sync;

    // Create synth chain with proper ordering
    drive = Synth(\yggDrive, [
      \in, driveBus,
      \out, context.out_b,
      \distDrive, 1.0,
      \distMix, 0.0
    ], target: context.xg, addAction: \addToTail);

    lineTap = Synth(\yggLineTap, [
      \in,  driveBus,
      \out, lineOutBus 
    ], target: drive, addAction: \addAfter);

    delay = Synth(\yggDelay, [
      \in, delayBus,
      \out, driveBus,
      \delayTime1, 0.25,
      \delayTime2, 0.5,
      \delayFB, 0.3,
      \delayMix, 0.3,
      \lfoBus, lfoBus,
      \modType, 0
    ], target: drive, addAction: \addBefore);

    lfo = Synth(\yggLFO, [
      \out, lfoBus,
      \freqA, 0.1,
      \freqB, 0.2,
      \style, 0
    ], target: context.xg, addAction: \addToHead);

    // Create voice group
    voiceGroup = Group.new(target: context.xg, addAction: \addToHead);

    // PRE-ALLOCATE 8 VOICES
    8.do
    {
      arg i;
      voices[i] = Synth(\yggVoice, [
        \out, voiceBuses[i],
        \voiceNum, i,
        \freq, 440,
        \amp, 0.5,
        \pressure, 0.0,
        \attack, defaultAttack,
        \release, defaultRelease,
        \hold, hold,
        \vibratoFreq, 5.0,
        \vibratoDepth, vibratoDepth,
        \harmonics, 0.0,
        \pitchBend, 0.0,
        \modDepth, 0.0,
        \modBus, modBuses[i],
        \lfoBus, lfoBus
      ], target: voiceGroup, addAction: \addToTail);
    };

    // CrossMod after voices
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
    ], target: voices[7], addAction: \addAfter);

    // VoiceMixer after CrossMod
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
    ], target: crossMod, addAction: \addAfter);

    // Register commands
    this.addCommands;

    "Ygg Engine initialized".postln;
  }

  loadSynthDefs
  {
    // LFO
    SynthDef(\yggLFO,
    {
      arg out=0, freqA=0.1, freqB=0.2, style=0;
      var oscA, oscB, lfo;

      oscA = SinOsc.ar(freqA);
      oscB = SinOsc.ar(freqB);

      lfo = Select.ar(K2A.ar(style), [
        oscA,
        (oscA + oscB) * 0.5,
        oscA * oscB,
        Lag.ar(oscA * oscB * 0.9, 0.1),
        SinOsc.ar(freqA + (oscB * freqA))
      ]);

      Out.ar(out, lfo);
    }).add;

    // Voice
    SynthDef(\yggVoice,
    {
      arg out=0,
          voiceNum=0,
          freq=440,
          amp=0.5,
          attack=0.1,
          release=1.0,
          hold=0.0,
          vibratoFreq=5.0,
          vibratoDepth=0.01,
          harmonics=0.0,
          pitchBend=0.0,
          pressure=0.0,
          modDepth=0.0,
          modBus=0,
          lfoBus=0;

      var sig, leftSig, rightSig;
      var currentAmp, ampControl, holdState, pressureState;
      var targetAmp, rateControl;
      var modSig, finalFreq;
      var sine, square, saw, morphedSig;
      var vibratoL, vibratoR;

      // Pitch modulation
      finalFreq = freq * pitchBend.midiratio;
      modSig = Select.ar(K2A.ar(modType), [
        In.ar(lfoBus, 1),
        (In.ar(lfoBus, 1) > 0) * 2 - 1
      ]);
      finalFreq = finalFreq + (modSig * modDepth * finalFreq * 0.5);

      // ARH Envelope
      currentAmp = LocalIn.ar(1);
      holdState = K2A.ar(currentAmp >= hold);
      targetAmp = Select.ar(holdState, [
        K2A.ar(pressure),
        K2A.ar(max(pressure, hold))
      ]);
      pressureState = K2A.ar(targetAmp > currentAmp);
      rateControl = Select.ar(pressureState, [
        K2A.ar(release.reciprocal),
        K2A.ar(attack.reciprocal)
      ]);
      ampControl = Lag.ar(targetAmp, rateControl.reciprocal);
      LocalOut.ar(ampControl);

      // Oscillator morphing
      sine = SinOsc.ar(finalFreq);
      square = Pulse.ar(finalFreq, 0.5);
      saw = LFSaw.ar(finalFreq);

      morphedSig = LinXFade2.ar(
        sine,
        LinXFade2.ar(square, saw, harmonics.linlin(0.5, 1.0, -1, 1)),
        harmonics.linlin(0, 0.5, -1, 1)
      );

      sig = morphedSig * ampControl * amp * 0.5;

      // Vibrato
      vibratoL = SinOsc.ar(vibratoFreq, 0);
      vibratoR = SinOsc.ar(vibratoFreq, pi * 0.5);

      leftSig = DelayC.ar(sig, 0.1,
        (vibratoL * vibratoDepth / finalFreq).abs.clip(0, 0.05)
      );

      rightSig = DelayC.ar(sig, 0.1,
        (vibratoR * vibratoDepth / finalFreq).abs.clip(0, 0.05)
      );

      leftSig = (leftSig * 2).softclip * 0.5;
      rightSig = (rightSig * 2).softclip * 0.5;

      Out.ar(out, [leftSig, rightSig]);
    }).add;

    // Mixer
    SynthDef(\yggVoiceMixer,
    {
      arg out=0,
          voice1Bus=0, voice2Bus=0, voice3Bus=0, voice4Bus=0,
          voice5Bus=0, voice6Bus=0, voice7Bus=0, voice8Bus=0;

      var mix;

      mix = (In.ar(voice1Bus, 2) +
             In.ar(voice2Bus, 2) +
             In.ar(voice3Bus, 2) +
             In.ar(voice4Bus, 2) +
             In.ar(voice5Bus, 2) +
             In.ar(voice6Bus, 2) +
             In.ar(voice7Bus, 2) +
             In.ar(voice8Bus, 2)) * 0.125;

      Out.ar(out, mix);
    }).add;

    // CrossMod
    SynthDef(\yggCrossMod,
    {
      arg voice1Bus=0, voice2Bus=0,
          voice3Bus=0, voice4Bus=0,
          voice5Bus=0, voice6Bus=0,
          voice7Bus=0, voice8Bus=0,
          out1=0, out2=0, out3=0, out4=0,
          out5=0, out6=0, out7=0, out8=0,
          routing=0;

      var v1, v2, v3, v4, v5, v6, v7, v8;
      var pair1, pair2, pair3, pair4;
      var mod12, mod34, mod56, mod78;
      var routingAudio;

      v1 = InFeedback.ar(voice1Bus, 2).sum;
      v2 = InFeedback.ar(voice2Bus, 2).sum;
      v3 = InFeedback.ar(voice3Bus, 2).sum;
      v4 = InFeedback.ar(voice4Bus, 2).sum;
      v5 = InFeedback.ar(voice5Bus, 2).sum;
      v6 = InFeedback.ar(voice6Bus, 2).sum;
      v7 = InFeedback.ar(voice7Bus, 2).sum;
      v8 = InFeedback.ar(voice8Bus, 2).sum;

      pair1 = v1 + v2;
      pair2 = v3 + v4;
      pair3 = v5 + v6;
      pair4 = v7 + v8;

      routingAudio = K2A.ar(routing);

      4.do
      {
        #mod12, mod34, mod56, mod78 = Select.ar(routingAudio, [
          [pair1, pair2, pair3, pair4], // Self
          [pair3, pair4, pair1, pair2], // Cross
          [pair2, pair1, pair4, pair3], // Neighbor
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

    // Delay
    SynthDef(\yggDelay,
    {
      arg in=0, out=0,
          delayTime1=0.25,
          delayTime2=0.5,
          delayFB=0.3,
          delayMix=0.3,
          lfoBus=0,
          modType=0,
          delayMod1=0.0,
          delayMod2=0.0;

      var input, delayed, wet, dry, fb;
      var modSig, time1, time2;

      input = In.ar(in, 2);
      modSig = Select.ar(K2A.ar(modType), [
        InFeedback.ar(lfoBus, 1),
        (InFeedback.ar(lfoBus, 1) > 0) * 2 - 1
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

    // Distortion
    SynthDef(\yggDrive,
    {
      arg in=0, out=0,
          distDrive=1.0,
          distMix=0.0;

      var input, driven, wet, dry;

      input = In.ar(in, 2);

      driven = input * distDrive.linexp(1.0, 10.0, 1.0, 100.0);
      driven = driven.clip2(1.0);
      driven = (driven * 1.2).fold2(1.0);
      driven = HPF.ar(driven, 60);
      driven = LPF.ar(driven, 5000);
      driven = LeakDC.ar(driven);
      driven = driven * distDrive.linlin(1.0, 10.0, 1.0, 0.3);

      wet = driven;
      dry = input;

      Out.ar(out, XFade2.ar(dry, wet, distMix * 2 - 1)*
            distMix.linlin(0.0, 1.0, 1.0, 0.3));
    }).add;

    SynthDef(\yggLineTap,
    {
      arg in=0, out=0;
      // Sum stereo output to mono and attenuate to keep mod depth sane
      Out.ar(out, In.ar(in, 2).sum * 0.5);
    }).add;
  }

  addCommands
  {
    this.addCommand(\note_on, "if",
    {
      arg msg;
      var note = msg[1].asInteger;
      var vel = msg[2];
      this.noteOn(note, vel);
    });

    this.addCommand(\note_off, "i",
    {
      arg msg;
      var note = msg[1].asInteger;
      this.noteOff(note);
    });

    this.addCommand(\attack, "f",
    {
      arg msg;
      defaultAttack = msg[1];
      this.setAllVoices(\attack, defaultAttack);
    });

    this.addCommand(\release, "f",
    {
      arg msg;
      defaultRelease = msg[1];
      this.setAllVoices(\release, defaultRelease);
    });

    this.addCommand(\hold, "f",
    {
      arg msg;
      hold = msg[1].clip(0, 1);
      this.setAllVoices(\hold, hold);
    });

    this.addCommand(\harmonics, "f",
    {
      arg msg;
      this.setAllVoices(\harmonics, msg[1].clip(0, 1));
    });

    this.addCommand(\vibrato_depth, "f",
    {
      arg msg;
      vibratoDepth = msg[1];
      this.setAllVoices(\vibratoDepth, vibratoDepth);
    });

    this.addCommand(\mod_depth, "f",
    {
      arg msg;
      this.setAllVoices(\modDepth, msg[1].clip(0, 1));
    });

    this.addCommand(\voice_mod_source, "ii",
    {
      arg msg;
      var voiceNum = msg[1].asInteger.clip(0, 7);
      var source = msg[2].asInteger;
      var bus;

      bus = case
        { source == 0 } { modBuses[voiceNum] }
        { source == 1 } { lfoBus }
        { source == 2 } { delayBus }
        { source == 3 } { lineOutBus }
        { modBuses[voiceNum] };

      voices[voiceNum].set(\modBus, bus.index);
    });

    this.addCommand(\routing, "i",
    {
      arg msg;
      routing = msg[1].asInteger.clip(0, 3);
      crossMod.set(\routing, routing);
    });

    this.addCommand(\lfo, "ffi",
    {
      arg msg;
      lfo.set(\freqA, msg[1], \freqB, msg[2], \style, msg[3].asInteger);
    });

    this.addCommand(\delay_time, "ff",
    {
      arg msg;
      delay.set(\delayTime1, msg[1], \delayTime2, msg[2]);
    });

    this.addCommand(\delay_fb, "f",
    {
      arg msg;
      delay.set(\delayFB, msg[1]);
    });

    this.addCommand(\delay_mix, "f",
    {
      arg msg;
      delay.set(\delayMix, msg[1]);
    });

    this.addCommand(\delay_mod, "ff",
    {
      arg msg;
      delay.set(\delayMod1, msg[1], \delayMod2, msg[2]);
    });

    this.addCommand(\dist_drive, "f",
    {
      arg msg;
      drive.set(\distDrive, msg[1].clip(1, 10));
    });

    this.addCommand(\dist_mix, "f",
    {
      arg msg;
      drive.set(\distMix, msg[1].clip(0, 1));
    });

    this.addCommand(\vibrato_depth_v, "if",
    {
      arg msg;
      var voiceNum = msg[1].asInteger.clip(0,7);
      voices[voiceNum].set(\vibratoDepth, msg[2]);
    });

    this.addCommand(\vibrato_freq_v, "if",
    {
      arg msg;
      var voiceNum = msg[1].asInteger.clip(0, 7);
      voices[voiceNum].set(\vibratoFreq, msg[2]);
    });

    this.addCommand(\pitch_bend, "if",
    {
      arg msg;
      var note     = msg[1].asInteger;
      var bend_st  = msg[2];
      var voiceNum = activeNotes[note];
      if(voiceNum.notNil)
      {
        voices[voiceNum].set(\pitchBend, bend_st);
      };
    });

    this.addCommand(\pressure, "if",
    {
      arg msg;
      var note     = msg[1].asInteger;
      var pressure = msg[2];
      var voiceNum = activeNotes[note];
      if(voiceNum.notNil)
      {
        voices[voiceNum].set(\pressure, pressure);
      };
    });

    this.addCommand(\delay_mod_type, "i",
    {
      arg msg;
      delay.set(\modType, msg[1].asInteger);
    });

    this.addCommand(\panic, "",
    {
      arg msg;
      this.panic;
    });
  }

  noteOn
  {
    arg note, vel=127;
    var voiceNum, freq, amp, existingVoice;

    freq = note.midicps;
    amp = vel.linlin(0, 127, 0, 1);

    existingVoice = activeNotes[note];

    if(existingVoice.notNil)
    {
      voiceNum = existingVoice;
    }
    {
      voiceNum = voiceIdx - 1;
      voiceIdx = (voiceIdx % 8) + 1;

      activeNotes.keysValuesDo
      {
        arg oldNote, oldVoice;
        if(oldVoice == voiceNum)
        {
          activeNotes.removeAt(oldNote);
        };
      };
    };

    voices[voiceNum].set(
      \freq, freq,
      \amp, amp,
      \pressure, 1.0
    );

    activeNotes[note] = voiceNum;
  }

  noteOff
  {
    arg note;
    var voiceNum;

    voiceNum = activeNotes[note];

    if(voiceNum.notNil)
    {
      voices[voiceNum].set(\pressure, 0.0);
    };
  }

  setAllVoices
  {
    arg param, value;
    8.do
    {
      arg i;
      voices[i].set(param, value);
    };
  }

  panic
  {
    activeNotes.keysDo { arg note; this.noteOff(note) };
    activeNotes.clear;
  }

  free
  {
    voices.do { arg v; if(v.notNil) { v.free } };
    if(voiceGroup.notNil) { voiceGroup.free };
    if(voiceMixer.notNil) { voiceMixer.free };
    if(crossMod.notNil) { crossMod.free };
    if(lfo.notNil) { lfo.free };
    if(delay.notNil) { delay.free };
    if(drive.notNil) { drive.free };
    if(lineTap.notNil) { lineTap.free };

    voiceBuses.do { arg b; b.free };
    modBuses.do { arg b; b.free };
    lfoBus.free;
    delayBus.free;
    driveBus.free;
    lineOutBus.free;
  }
}
