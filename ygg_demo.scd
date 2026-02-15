// ygg_demo.scd
// Demo script for Ygg drone synthesizer
// Requires: ygg_synths.scd and ygg_manager.scd

// Load the manager (which will load SynthDefs if needed)
(
thisProcess.nowExecutingPath.dirname +/+ "ygg_manager.scd".load;
)

// Initialize the engine
(
~ygg.init;
)

(
~ygg.free;
)

// ====================================================================
// DEMO SCRIPT
// ====================================================================
(
fork
{
  // Wait for engine to initialize
  1.wait;

  "=== YGG ENGINE DEMO ===".postln;
  "".postln;

  // ================================================================
  // 1. Basic drone with held notes
  // ================================================================
  "1. Creating evolving drone with hold...".postln;
  ~ygg.setHold(0.3);  // hold at 30% volume
  ~ygg.setAllVoices(\attack, 10);
  ~ygg.setAllVoices(\release, 10);
  ~ygg.setAllVoices(\vibratoFreq, 6.0);
  ~ygg.setAllVoices(\harmonics, 1.0);
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
  5.wait;

  ~ygg.setRouting(1);  // cross
  "Routing: cross".postln;
  5.wait;

  ~ygg.setRouting(2);  // loop
  "Routing: loop".postln;
  5.wait;

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

  10.wait;

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
  ~ygg.setHold(0.0);
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
~ygg.setHold(0.0);

// Set vibrato depth
~ygg.setVibratoDepth(0.05);

// Change cross-modulation routing (0=neighbor, 1=cross, 2=loop)
~ygg.setRouting(1);

// Set LFO (freqA, freqB, style: 0=single, 1=sum, 2=product, 3=fm)
~ygg.setLFO(0.1, 0.2, 1);

// Set delay (time1, time2, mod1, mod2, feedback, mix, modType: 0=smooth, 1=jump)
~ygg.setDelay(0.25, 0.5, 0.1, 0.15, 0.4, 0.5, 0);

// Set distortion (drive, mix)
~ygg.setDrive(1.0, 1.0);

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

~ygg.setAllVoices(\hold, 0.0);
~ygg.setAllVoices(\pressure, 0.0);
