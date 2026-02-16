// ygg_synths.scd
// Shared SynthDef definitions for Ygg drone synthesizer
// Load this first, then use with ygg_manager.scd or Engine_Ygg.sc

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

  // LFO modes - use SelectX for audio-rate selection with interpolation
  lfo = SelectX.ar(
    style.clip(0, 3),  // selector
    [
      oscA,                                  // 0: single (freqA only)
      (oscA + oscB) * 0.5,                   // 1: sum
      oscA * oscB,                           // 2: product
      SinOsc.ar(freqA + (oscB * freqB * 2))  // 3: soft FM
    ]
  );

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
      attack=0.1,
      release=1.0,
      hold=0.0,              // global hold level (0-1)
      vibratoFreq=5.0,
      vibratoDepth=0.01,     // global vibrato depth
      harmonics=0.0,         // 0=sine, 0.5=square, 1.0=saw
      pitchBend=0.0,         // in semitones
      pressure=0.0,          // Control via pressure (0-1), no gate!
      modDepth=0.0,          // cross-mod depth
      modBus=0,              // bus for modulation source
      lfoBus=0;              // global LFO bus

  var sig, leftSig, rightSig;
  var currentAmp, ampControl, holdState, pressureState;
  var targetAmp, rateControl;
  var modSig, finalFreq;
  var sine, square, saw, morphedSig;
  var vibratoL, vibratoR;

  // Pitch bend and modulation
  finalFreq = freq * pitchBend.midiratio;
  modSig    = InFeedback.ar(modBus, 1);  // Use InFeedback to read previous cycle

  // DEBUG: Poll modDepth to see what value the synth actually has
  //modDepth.poll(10, "modDepth");
  //modSig.poll(10, "modSig");

  finalFreq = finalFreq + (modSig * modDepth * finalFreq * 0.5);

  // ARH Envelope: State-based amplitude control with hold threshold
  // Initialize amplitude at zero (feedback from previous sample)
  currentAmp = LocalIn.ar(1);

  // Determine target amplitude based on current state
  // Once amp crosses above hold, it cannot fall below hold
  holdState = K2A.ar(currentAmp >= hold);
  targetAmp = Select.ar(holdState, [
    K2A.ar(pressure),              // Below hold: follow pressure directly
    K2A.ar(max(pressure, hold))    // Above hold: clamp to hold minimum
  ]);

  // Calculate slew rate based on direction (attack vs release)
  pressureState = K2A.ar(targetAmp > currentAmp);
  rateControl = Select.ar(pressureState, [
    K2A.ar(release.reciprocal),   // Falling: use release time
    K2A.ar(attack.reciprocal)     // Rising: use attack time
  ]);

  // Smooth amplitude transitions
  ampControl = Lag.ar(targetAmp, rateControl.reciprocal);

  // Feed back the amplitude for next sample
  LocalOut.ar(ampControl);

  // Scale by amp parameter and leave headroom for 8 voices
  // ampControl = ampControl * amp * 0.5;
  // ampControl = ampControl * 0.5;

  // Oscillator morphing: sine -> square -> saw
  sine = SinOsc.ar(finalFreq);
  square = Pulse.ar(finalFreq, 0.5);
  saw = LFSaw.ar(finalFreq);

  // Morph between waveforms: 0-0.5 blends sine->square, 0.5-1.0 blends square->saw
  morphedSig = LinXFade2.ar(
    XFade2.ar(sine, square, harmonics.linlin(0, 0.5, -1, 1)),
    XFade2.ar(square, saw, harmonics.linlin(0.5, 1.0, -1, 1)),
    harmonics.linlin(0, 1, -1, 1)
  );

  sig = morphedSig * ampControl;

  // Leslie-like vibrato for stereo expansion - always apply delay
  vibratoL = SinOsc.ar(vibratoFreq, 0);
  vibratoR = SinOsc.ar(vibratoFreq, pi * 0.5);

  // always use delay, depth controls amount
  leftSig = DelayC.ar(sig, 0.1,
    (vibratoL * vibratoDepth / finalFreq).abs.clip(0, 0.05)
  );

  rightSig = DelayC.ar(sig, 0.1,
    (vibratoR * vibratoDepth / finalFreq).abs.clip(0, 0.05)
  );

  // Soft limiting to prevent runaway feedback
  leftSig = (leftSig * 2).softclip * 0.5;
  rightSig = (rightSig * 2).softclip * 0.5;

  Out.ar(out, [leftSig, rightSig]);
}).add;

// ====================================================================
// VOICE MIXER: Sums all 8 voices to output
// ====================================================================
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
      routing=0;  // 0=self, 1=cross, 2=neighbor, 3=loop

  var v1, v2, v3, v4, v5, v6, v7, v8;
  var pair1, pair2, pair3, pair4;
  var mod12, mod34, mod56, mod78;
  var routingAudio;
  var i;

  // Read voice pairs (summed L+R to mono)
  // Use InFeedback to avoid conflicting with VoiceMixer reading same buses
  v1 = InFeedback.ar(voice1Bus, 2).sum;
  v2 = InFeedback.ar(voice2Bus, 2).sum;
  v3 = InFeedback.ar(voice3Bus, 2).sum;
  v4 = InFeedback.ar(voice4Bus, 2).sum;
  v5 = InFeedback.ar(voice5Bus, 2).sum;
  v6 = InFeedback.ar(voice6Bus, 2).sum;
  v7 = InFeedback.ar(voice7Bus, 2).sum;
  v8 = InFeedback.ar(voice8Bus, 2).sum;

  // Sum pairs
  pair1 = v1 + v2;
  pair2 = v3 + v4;
  pair3 = v5 + v6;
  pair4 = v7 + v8;

  // Convert routing to audio rate (will update each sample)
  routingAudio = K2A.ar(routing);

  // 4 iterations to settle feedback
  4.do
  {
    // Select modulation sources based on current routing
    #mod12, mod34, mod56, mod78 = Select.ar(routingAudio, [
      // 0: pair self-modulation (12 <-> 12, 34 <-> 34, etc)
      [pair1, pair2, pair3, pair4],
      // 1: cross (12 <-> 56, 34 <-> 78)
      [pair3, pair4, pair1, pair2],
      // 2: neighbor (12 <-> 34, 56 <-> 78)
      [pair2, pair1, pair4, pair3],
	  // 3: loop (12 -> 34 -> 56 -> 78 -> 12)
	  [pair4, pair1, pair2, pair3]
    ]);

    // Update pairs with feedback (reduced amount and stronger limiting)
    pair1 = (v1 + v2 + (mod12 * 0.2)).clip2(2).softclip;
    pair2 = (v3 + v4 + (mod34 * 0.2)).clip2(2).softclip;
    pair3 = (v5 + v6 + (mod56 * 0.2)).clip2(2).softclip;
    pair4 = (v7 + v8 + (mod78 * 0.2)).clip2(2).softclip;
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
  modSig = Select.kr(modType, [
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

  // RAT-style aggressive distortion
  // Pre-gain boost
  driven = input * distDrive.linexp(1.0, 10.0, 1.0, 100.0);

  // Hard clipping (RAT uses op-amp clipping)
  driven = driven.clip2(1.0);

  // Add some asymmetry for more character
  driven = (driven * 1.2).fold2(1.0);

  // High-pass filter (RAT has a ~60Hz HPF)
  driven = HPF.ar(driven, 60);

  // Low-pass filter for smoothing (RAT has ~5kHz LPF)
  driven = LPF.ar(driven, 5000);

  // DC blocker
  driven = LeakDC.ar(driven);

  // Output gain compensation (reduce volume as drive increases)
  driven = driven * distDrive.linlin(1.0, 10.0, 1.0, 0.3);

  // Mix
  wet = driven;
  dry = input;

  Out.ar(out, XFade2.ar(dry, wet, distMix * 2 - 1)*
            distMix.linlin(0.0, 1.0, 1.0, 0.3));
  //Out.ar(out, XFade2.ar(dry, wet, distMix * 2 - 1));
}).add;

"Ygg SynthDefs loaded.".postln;
)
