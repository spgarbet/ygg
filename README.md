# Ygg Drone Synthesizer Engine

A Lyra-8 inspired drone synthesizer for SuperCollider and Norns, designed for MPE controllers and evolving spectral harmonies.

## Overview

Ygg is an 8-voice polyphonic drone synthesizer with:
- **Voice stealing** from oldest voice (ring buffer allocation)
- **MPE support** (pitch bend and pressure per note)
- **Cross-modulation matrix** with 3 routing modes
- **Harmonics morphing** (sine → square → saw)
- **Leslie-style vibrato** for stereo expansion
- **Hold mode** for sustained drones
- **2-tap modulated delay**
- **Tube-style distortion**
- **Global LFO** with 4 modes

## Architecture

### Signal Flow
```
8 Voices (stereo) → Cross-Modulation → Delay → Distortion → Main Out
                         ↑
                      Global LFO
```

### Voice Parameters (per voice)
- `freq` - Base frequency in Hz
- `amp` - Amplitude (0-1)
- `attack` - Attack time in seconds
- `release` - Release time in seconds
- `vibratoFreq` - Vibrato rate in Hz (0 = mono, >0 = stereo)
- `harmonics` - Waveform morph (0=sine, 0.5=square, 1.0=saw)
- `pitchBend` - MPE pitch bend in semitones
- `pressure` - MPE pressure (0-1, scales amplitude)
- `modDepth` - Cross-modulation depth in Hz
- `modSrc` - Modulation source (voice/lfo/predelay/predrive/main)

### Global Parameters
- `hold` - Sustain level when note released (0-1)
- `vibratoDepth` - Global vibrato depth
- `routing` - Cross-mod routing (0=neighbor, 1=cross, 2=loop)

### Cross-Modulation Routing
Voice pairs: 1-2, 3-4, 5-6, 7-8

**Neighbor (0)**: 1-2 ↔ 3-4, 5-6 ↔ 7-8  
**Cross (1)**: 1-2 ↔ 5-6, 3-4 ↔ 7-8  
**Loop (2)**: 1-2 → 3-4 → 5-6 → 7-8 → 1-2

The cross-modulation uses 4 iterations to settle feedback, creating analogue-like behavior.

### LFO Modes
- **Single (0)**: Use freqA only
- **Sum (1)**: freqA + freqB
- **Product (2)**: freqA × freqB
- **FM (3)**: Soft frequency modulation

### Delay Parameters
- `delayTime1` - First tap time (0-2 seconds)
- `delayTime2` - Second tap time (0-2 seconds)
- `delayMod1` - First tap modulation depth
- `delayMod2` - Second tap modulation depth
- `delayFB` - Feedback amount (0-1)
- `delayMix` - Dry/wet mix (0-1)
- `delayModSrc` - Modulation source (lfo/self)
- `delayModType` - Modulation style (0=smooth, 1=jump/square)

### Distortion Parameters
- `distDrive` - Drive amount (1-10+)
- `distMix` - Dry/wet mix (0-1)

## Installation

### For SuperCollider standalone:
1. Copy `ygg_engine.scd` and `ygg_demo.scd` to your work directory
2. Load the engine: `"ygg_engine.scd".load;`
3. Run the demo: `"ygg_demo.scd".load;`

### For Norns:
1. Copy `Engine_Ygg.sc` to `~/dust/code/` on the Norns
2. The engine will be available in scripts via `engine.name = "Ygg"`

## Usage Examples

### Basic Usage (SuperCollider)
```supercollider
// Initialize
~ygg.init;

// Play a note (MIDI note, velocity)
~ygg.noteOn(60, 100);

// Release a note
~ygg.noteOff(60);

// Set hold level (notes sustain at this level when released)
~ygg.setHold(0.3);  // 30% volume hold

// Change harmonics (all voices)
~ygg.setAllVoices(\harmonics, 0.7);

// Change cross-modulation routing
~ygg.setRouting(2);  // loop mode

// Add delay
~ygg.setDelay(0.25, 0.5, 0.1, 0.15, 0.4, 0.5, 0);

// Add distortion
~ygg.setDrive(3.0, 0.6);
```

### MPE Control
```supercollider
// Pitch bend (in semitones)
~ygg.setPitchBend(60, 2.0);  // +2 semitones on note 60

// Pressure (affects amplitude)
~ygg.setPressure(60, 0.8);  // 80% pressure
```

### Individual Voice Control
```supercollider
// Set parameter on voice 0
~ygg.setVoiceParam(0, \harmonics, 0.8);
~ygg.setVoiceParam(0, \vibratoFreq, 7.0);
~ygg.setVoiceParam(0, \modDepth, 200);
```

### Norns Usage
```lua
-- In your Norns script

engine.name = "Ygg"

-- Play note
engine.noteOn(60, 0.8)

-- Release note
engine.noteOff(60)

-- Set global hold
engine.hold(0.3)

-- Set vibrato depth
engine.vibratoDepth(0.05)

-- Set routing (0=neighbor, 1=cross, 2=loop)
engine.routing(1)

-- LFO settings
engine.lfoFreqA(0.1)
engine.lfoFreqB(0.2)
engine.lfoStyle(1)  -- 0=single, 1=sum, 2=product, 3=fm

-- Delay settings
engine.delayTime1(0.25)
engine.delayTime2(0.5)
engine.delayMix(0.5)

-- Distortion
engine.distDrive(2.0)
engine.distMix(0.4)

-- MPE
engine.pitchBend(60, 2.0)  -- note, semitones
engine.pressure(60, 0.8)   -- note, pressure
```

## Design Notes

### Voice Allocation
The code uses a ring buffer for voice stealing. The `voiceIdx` counter (1-8) tracks the next voice to steal, incrementing with each new note. This ensures the oldest voice is always replaced first, which is important for maintaining the drone character even during release phases.

### Hold Mode
The `hold` parameter creates the signature Lyra-8 sustain behavior. When a note is released (`gate=0`), instead of fully decaying, the voice sustains at the hold level. If the hold level is 0, notes will fully release. If greater than 0, notes create an evolving drone bed. If a note doesn't reach its full amplitude before release, it will hold at whatever maximum it achieved.

### Leslie Vibrato
When `vibratoFreq > 0`, each voice creates stereo spread using phase-offset vibrato (90° between L/R). The code uses time-domain delay modulation rather than pitch modulation, mimicking a Leslie speaker's Doppler effect. At `vibratoFreq = 0`, voices are mono and identical in both channels.

### Cross-Modulation Settling
The cross-modulation network requires iterative solving because voices modulate each other in feedback loops. The code performs 4 iterations per audio block to settle the feedback, similar to solving a system of coupled differential equations. This creates the characteristic "analogue-like" instability and richness.

### Soft Limiting
Both voices and cross-modulation paths use `.softclip` to prevent runaway feedback while maintaining musical saturation characteristics. This is critical for stability with high modulation depths.

## Performance Considerations

The engine is optimized for Raspberry Pi 4B:
- Uses efficient DelayC UGens instead of buffer-based delays
- Cross-modulation settling limited to 4 iterations
- Voice outputs are hard-limited to prevent CPU spikes
- All buses are properly pre-allocated

Expected CPU usage: ~30-40% on RPi4B with all 8 voices active and effects engaged.

## Recommended Settings for Drones

### Slow Evolving Pad
```supercollider
~ygg.setAllVoices(\attack, 2.0);
~ygg.setAllVoices(\release, 5.0);
~ygg.setHold(0.4);
~ygg.setAllVoices(\harmonics, 0.2);
~ygg.setAllVoices(\vibratoFreq, 3.0);
~ygg.setVibratoDepth(0.03);
~ygg.setRouting(0);  // neighbor
~ygg.setDelay(0.5, 0.75, 0.1, 0.15, 0.3, 0.4, 0);
```

### Chaotic Feedback
```supercollider
~ygg.setAllVoices(\modDepth, 400);
~ygg.setRouting(2);  // loop
~ygg.setAllVoices(\harmonics, 0.8);
~ygg.setDrive(4.0, 0.7);
```

### Spectral Harmony
```supercollider
// Play harmonic series: fundamental + overtones
[48, 60, 67, 72, 76, 79, 82, 84].do { |note, i|
    ~ygg.noteOn(note, 0.9 - (i * 0.05));
};
~ygg.setHold(0.5);
~ygg.setAllVoices(\harmonics, 0.3);
```

## Future Enhancements

Potential additions for V2:
- Per-voice LFO routing selection
- Additional modulation sources (envelope followers)
- Reverb module
- Envelope shape selection (exponential/linear)
- MIDI learn for parameter mapping
- Preset system

## Credits

Inspired by the SOMA Laboratory Lyra-8 Organismic Synthesizer.  
Designed for Monome Norns (ShieldXL) with MPE controller support.

## License

This implementation is provided as-is for educational and creative use.
