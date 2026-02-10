// Ygg Synth Engine - Lyra-8 inspired drone synthesizer
// Designed for Norns + MPE controllers

(
// ====================================================================
// UTILITY SYNTHDEF: Global LFO
// ====================================================================
SynthDef(\yggLFO,
{
  arg out=0, freqA=0.1, freqB=0.2, style=0;
  var lfo, oscA, oscB;
  
  oscA = SinOsc.ar(freqA);
  oscB = SinOsc.ar(freqB);
  
  lfo = Select.ar(style, [
    oscA,                           // 0: single (freqA only)
    (oscA + oscB) * 0.5,           // 1: sum
    oscA * oscB,                    // 2: product
    SinOsc.ar(freqA + (oscB * freqB * 2))  // 3: soft FM
  ]);
  
  Out.ar(out, lfo);
}).add;

// ====================================================================
// CORE SYNTHDEF: Ygg Voice
// ====================================================================
SynthDef(\yggVoice,
{
  arg out=0, 
      voiceNum=0,
      freq=440, 
      amp=0.5,
      gate=1,
      attack=0.1, 
      release=1.0,
      hold=0.0,              // global hold level (0-1)
      vibratoFreq=5.0,
      vibratoDepth=0.01,     // global vibrato depth
      harmonics=0.0,         // 0=sine, 0.5=square, 1.0=saw
      pitchBend=0.0,         // in semitones
      pressure=1.0,          // MPE pressure (0-1)
      modDepth=0.0,          // cross-mod depth
      modBus=0,              // bus for modulation source
      lfoBus=0,              // global LFO bus
      predelayBus=0,         // predelay bus for modulation
      predriveBus=0;         // predrive bus for modulation
  
  var sig, leftSig, rightSig;
  var env, holdEnv, currentAmp;
  var modSig, finalFreq;
  var sine, square, saw, morphedSig;
  var vibratoL, vibratoR, panning;
  
  // Pitch bend and modulation
  finalFreq = freq * pitchBend.midiratio;
  modSig = In.ar(modBus, 1);
  finalFreq = finalFreq + (modSig * modDepth * finalFreq * 0.5);
  
  // Envelope with hold
  env = EnvGen.ar(
    Env.asr(attack, 1.0, release),
    gate,
    doneAction: 2
  );
  
  // Hold logic: sustain at hold level when gate releases
  holdEnv = Select.ar(gate, [
    DC.ar(hold),  // when gate=0, output hold level
    env           // when gate=1, follow envelope
  ]);
  
  // Apply pressure to amplitude
  currentAmp = amp * env * pressure.linlin(0, 1, 0.5, 1.0);
  currentAmp = currentAmp.max(holdEnv * amp);
  
  // Oscillator morphing: sine -> square -> saw
  sine = SinOsc.ar(finalFreq);
  square = Pulse.ar(finalFreq, 0.5);
  saw = LFSaw.ar(finalFreq);
  
  morphedSig = Select.ar(
    (harmonics * 2).clip(0, 2),
    [
      sine,
      XFade2.ar(sine, square, (harmonics * 4 - 1).clip(-1, 1)),
      XFade2.ar(square, saw, (harmonics * 4 - 3).clip(-1, 1))
    ]
  );
  
  sig = morphedSig * currentAmp;
  
  // Leslie-like vibrato for stereo expansion
  vibratoL = SinOsc.ar(vibratoFreq, 0);
  vibratoR = SinOsc.ar(vibratoFreq, pi * 0.5);
  
  leftSig = Select.ar(
    (vibratoFreq > 0.01),
    [
      sig,  // mono when vibrato freq ~ 0
      DelayC.ar(sig, 0.1, 
        (vibratoL * vibratoDepth / finalFreq).abs.clip(0, 0.05))
    ]
  );
  
  rightSig = Select.ar(
    (vibratoFreq > 0.01),
    [
      sig,  // mono when vibrato freq ~ 0
      DelayC.ar(sig, 0.1, 
        (vibratoR * vibratoDepth / finalFreq).abs.clip(0, 0.05))
    ]
  );
  
  // Soft limiting to prevent runaway feedback
  leftSig = (leftSig * 2).softclip * 0.5;
  rightSig = (rightSig * 2).softclip * 0.5;
  
  Out.ar(out, [leftSig, rightSig]);
}).add;

// ====================================================================
// CROSS-MODULATION FEEDBACK PROCESSOR
// ====================================================================
SynthDef(\yggCrossMod,
{
  arg voice1Bus=0, voice2Bus=0, 
      voice3Bus=0, voice4Bus=0,
      voice5Bus=0, voice6Bus=0,
      voice7Bus=0, voice8Bus=0,
      out1=0, out2=0, out3=0, out4=0,
      out5=0, out6=0, out7=0, out8=0,
      routing=0;  // 0=neighbor, 1=cross, 2=loop
  
  var v1, v2, v3, v4, v5, v6, v7, v8;
  var pair1, pair2, pair3, pair4;
  var mod12, mod34, mod56, mod78;
  var i;
  
  // Read voice pairs (summed L+R to mono)
  v1 = In.ar(voice1Bus, 2).sum;
  v2 = In.ar(voice2Bus, 2).sum;
  v3 = In.ar(voice3Bus, 2).sum;
  v4 = In.ar(voice4Bus, 2).sum;
  v5 = In.ar(voice5Bus, 2).sum;
  v6 = In.ar(voice6Bus, 2).sum;
  v7 = In.ar(voice7Bus, 2).sum;
  v8 = In.ar(voice8Bus, 2).sum;
  
  // Sum pairs
  pair1 = v1 + v2;
  pair2 = v3 + v4;
  pair3 = v5 + v6;
  pair4 = v7 + v8;
  
  // 4 iterations to settle feedback
  4.do
  {
    // Routing: neighbor, cross, loop
    #mod12, mod34, mod56, mod78 = Select.ar(routing, [
      // 0: neighbor (12 <-> 34, 56 <-> 78)
      [pair2, pair1, pair4, pair3],
      // 1: cross (12 <-> 56, 34 <-> 78)
      [pair3, pair4, pair1, pair2],
      // 2: loop (12 -> 34 -> 56 -> 78 -> 12)
      [pair4, pair1, pair2, pair3]
    ]);
    
    // Update pairs with feedback (soft limiting)
    pair1 = (v1 + v2 + (mod12 * 0.3)).softclip;
    pair2 = (v3 + v4 + (mod34 * 0.3)).softclip;
    pair3 = (v5 + v6 + (mod56 * 0.3)).softclip;
    pair4 = (v7 + v8 + (mod78 * 0.3)).softclip;
  };
  
  // Output settled modulation signals
  Out.ar(out1, mod12);
  Out.ar(out2, mod12);
  Out.ar(out3, mod34);
  Out.ar(out4, mod34);
  Out.ar(out5, mod56);
  Out.ar(out6, mod56);
  Out.ar(out7, mod78);
  Out.ar(out8, mod78);
}).add;

// ====================================================================
// EFFECT: 2-Tap Variable Delay
// ====================================================================
SynthDef(\yggDelay,
{
  arg in=0, out=0,
      delayTime1=0.25, delayTime2=0.5,
      delayMod1=0.1, delayMod2=0.15,
      delayFB=0.3,
      delayMix=0.3,
      lfoBus=0,
      modType=0;  // 0=smooth, 1=jump
  
  var input, delayed, lfo, modSig;
  var time1, time2, fb;
  var wet, dry;
  
  input = In.ar(in, 2);
  lfo = In.ar(lfoBus, 1);
  
  // Modulation: smooth or jump (square wave)
  modSig = Select.ar(modType, [
    lfo,                    // 0: smooth (sine)
    (lfo > 0).linlin(0, 1, -1, 1)  // 1: jump (square)
  ]);
  
  // Modulated delay times
  time1 = (delayTime1 + (modSig * delayMod1)).clip(0.001, 2.0);
  time2 = (delayTime2 + (modSig * delayMod2)).clip(0.001, 2.0);
  
  // Feedback delay network
  fb = LocalIn.ar(2);
  delayed = DelayC.ar(input + (fb * delayFB), 2.0, [time1, time2]);
  delayed = delayed.softclip;  // prevent runaway
  LocalOut.ar(delayed);
  
  // Mix
  wet = delayed;
  dry = input;
  
  Out.ar(out, XFade2.ar(dry, wet, delayMix * 2 - 1));
}).add;

// ====================================================================
// EFFECT: Tube-Style Distortion
// ====================================================================
SynthDef(\yggDrive,
{
  arg in=0, out=0,
      distDrive=1.0,
      distMix=0.0;
  
  var input, driven, wet, dry;
  
  input = In.ar(in, 2);
  
  // Tube-style soft saturation
  driven = (input * distDrive).tanh;
  driven = LeakDC.ar(driven);
  
  // Additional warmth via even harmonics
  driven = (driven + (driven.squared * 0.2)).softclip;
  
  // Mix
  wet = driven * 0.7;  // compensate for gain
  dry = input;
  
  Out.ar(out, XFade2.ar(dry, wet, distMix * 2 - 1));
}).add;

)
