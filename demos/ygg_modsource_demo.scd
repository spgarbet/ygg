// ====================================================================
// YGG MODULATION SOURCE DEMO
// Shows routing matrix vs direct LFO vs line output modulation
// ====================================================================

(
thisProcess.nowExecutingPath.dirname +/+ "ygg_manager.scd".load;
)

(
fork {
  "=== YGG MODULATION SOURCE DEMONSTRATION ===".postln;
  "".postln;

  // Setup
  ~ygg.setHold(0.0);
  ~ygg.setAllVoices(\attack, 0.5);
  ~ygg.setAllVoices(\release, 2.0);
  ~ygg.setAllVoices(\harmonics, 0.0);  // Pure sine
  ~ygg.setVibratoDepth(0.0);  // No vibrato

  // ================================================================
  // DEMO 1: Cross-Mod Routing Matrix (Default)
  // ================================================================
  "".postln;
  "=== DEMO 1: Cross-Mod Routing Matrix (Default) ===".postln;
  "Playing single note - modulation from routing matrix".postln;
  "".postln;

  ~ygg.noteOn(60, 100);
  2.wait;

  "Setting modDepth to 0.6 (uses crossMod routing)...".postln;
  ~ygg.setAllVoices(\modDepth, 0.6);
  ~ygg.setRouting(0);  // Self-modulation

  5.wait;
  "Hear slow self-modulation wobble from routing matrix".postln;

  ~ygg.noteOff(60);
  2.wait;

  // ================================================================
  // DEMO 2: Direct LFO Modulation (Bypass Routing Matrix)
  // ================================================================
  "".postln;
  "=== DEMO 2: Direct LFO Modulation ===".postln;
  "Voice reads directly from LFO, ignoring routing matrix".postln;
  "".postln;

  // Setup LFO
  ~ygg.setLFO(2.0, 5.0, 1);  // Sum mode: 2Hz + 5Hz

  ~ygg.noteOn(60, 100);
  1.wait;

  "Switching voice 0 to read from LFO bus...".postln;
  ~ygg.setVoiceModSource(0, 'lfo');
  ~ygg.setAllVoices(\modDepth, 0.3);  // Lower depth for LFO

  5.wait;
  "Hear faster LFO modulation (2Hz + 5Hz pattern)".postln;

  2.wait;
  "Changing LFO to Chaos mode...".postln;
  ~ygg.setLFO(3.0, 7.0, 3);  // Chaos mode

  5.wait;
  "Unpredictable chaos modulation".postln;

  ~ygg.noteOff(60);
  2.wait;

  // ================================================================
  // DEMO 3: Line Output Modulation
  // ================================================================
  "".postln;
  "=== DEMO 3: Line Output as Modulation Source ===".postln;
  "Voice modulates itself using the final mix".postln;
  "".postln;

  ~ygg.noteOn(60, 100);
  1.wait;

  "Switching voice 0 to read from line output...".postln;
  ~ygg.setVoiceModSource(0, 'lineout');
  ~ygg.setAllVoices(\modDepth, 0.2);  // Very low depth

  5.wait;
  "Self-modulation using own output (can create feedback)".postln;

  ~ygg.noteOff(60);
  2.wait;

  // ================================================================
  // DEMO 4: Comparison - All Three Sources
  // ================================================================
  "".postln;
  "=== DEMO 4: Three Voices, Three Sources ===".postln;
  "Voice 0: Routing matrix, Voice 1: LFO, Voice 2: Line out".postln;
  "".postln;

  // Play three notes
  ~ygg.noteOn(60, 100);
  ~ygg.noteOn(64, 100);
  ~ygg.noteOn(67, 100);

  1.wait;

  // Set different sources
  "Configuring modulation sources...".postln;
  ~ygg.setVoiceModSource(0, 'crossmod');  // Default routing
  ~ygg.setVoiceModSource(1, 'lfo');       // Direct LFO
  ~ygg.setVoiceModSource(2, 'lineout');   // Line output

  // Setup
  ~ygg.setLFO(3.0, 7.0, 3);  // Chaos LFO
  ~ygg.setRouting(0);         // Self-modulation
  ~ygg.setAllVoices(\modDepth, 0.5);

  10.wait;
  "Three different modulation patterns simultaneously!".postln;
  "- Voice 0 (60): Slow self-modulation from routing".postln;
  "- Voice 1 (64): Fast chaos from LFO".postln;
  "- Voice 2 (67): Feedback from line output".postln;

  // Cleanup
  2.wait;
  ~ygg.noteOff(60);
  ~ygg.noteOff(64);
  ~ygg.noteOff(67);
  3.wait;

  // ================================================================
  // DEMO 5: All LFO Modes with Direct Modulation
  // ================================================================
  "".postln;
  "=== DEMO 5: LFO Modes Direct to Voice ===".postln;
  "".postln;

  ~ygg.noteOn(60, 100);
  ~ygg.setVoiceModSource(0, 'lfo');
  ~ygg.setAllVoices(\modDepth, 0.4);

  1.wait;

  "LFO Mode 0: Single (2Hz)".postln;
  ~ygg.setLFO(2.0, 5.0, 0);
  4.wait;

  "LFO Mode 1: Sum (2Hz + 5Hz)".postln;
  ~ygg.setLFO(2.0, 5.0, 1);
  4.wait;

  "LFO Mode 2: Product (2Hz * 5Hz)".postln;
  ~ygg.setLFO(2.0, 5.0, 2);
  4.wait;

  "LFO Mode 3: Chaos".postln;
  ~ygg.setLFO(3.0, 7.0, 3);
  4.wait;

  ~ygg.noteOff(60);
  2.wait;

  "".postln;
  "=== DEMONSTRATION COMPLETE ===".postln;
  "".postln;
  "Summary:".postln;
  "- setVoiceModSource(voiceNum, source) changes mod input".postln;
  "- 'crossmod': Uses routing matrix (default)".postln;
  "- 'lfo': Direct LFO modulation (fast, precise patterns)".postln;
  "- 'lineout': Self-modulation from final mix (feedback)".postln;
  "- Each voice can have a different modulation source!".postln;

};
)
