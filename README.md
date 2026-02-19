# Ygg Drone Synthesizer Engine

A Lyra-8 inspired drone synthesizer for SuperCollider and Norns, designed for MPE controllers and evolving spectral harmonies.

![](img/screenshot.png)

[Jörmungandr](https://soundcloud.com/shawn-garbett/jormungandr) Demo seed: 42, B locrian, 10s. 

## Overview

Ygg is an 8-voice polyphonic drone synthesizer with:
- **Voice stealing** from oldest voice (ring buffer allocation)
- **MPE support** (pitch bend and pressure per note)
- **Cross-modulation matrix** with 4 routing modes and local voice overrides.
- **Harmonics morphing** (sine → square → saw)
- **Leslie-style vibrato** for stereo expansion
- **Hold mode** for sustained drones
- **2-tap modulated delay**
- **Tube-style distortion** _It goes to 11!_
- **Global LFO** with 4 modes

## Architecture

### Main Screen

On the main screen you will see Yggdrasil and it has 8 points that can be navigated on the tree. These are patches and can be changed live. Hitting the K2 on this screen saves the current state so it persists over reboots. The E2 and E3 encoders change the current patch. The current patch appears at the top left and they have reference names: Sol, Mani, Huginn, Muninn, Asgard, Midgard, Jormun and Gandr. One can scroll through screens using the K3 (and back with K2), and use the encoders to change parameters. The current page appears in the upper right. The last page is the Demo page and when one hits the K3 it begins a drone demo sequence, that is randomly generated based on a pattern and the user can specify the random seed used as well as the tonic note and scale. 

It also supports MIDI MPE input. 

### Signal Flow

```
8 Voices (to individual buses) → Voice Mixer (sum to stereo) → Delay → Distortion → Main Out
                                      ↓
                                 Cross-Modulation (feedback)
                                      ↑          ↑        
                                  Global LFO  Main Out
```

### Voice Parameters (per voice)

- `freq` - Base frequency in Hz
- `amp` - Amplitude (0-1)
- `attack` - Attack time in seconds
- `release` - Release time in seconds
- `hold` - Hold depth (0-1)
- `vibrato_freq` - Vibrato rate in Hz (0 = mono, >0 = stereo)
- `vibrato_depth` - Depth of Vibrato(0, 1)
- `harmonics` - Waveform morph (0=sine, 0.5=square, 1.0=saw)
- `pitch_bend` - MPE pitch bend in semitones
- `pressure` - MPE pressure (0-1, scales amplitude)
- `voice_mod_source` - Modulation source (0=crossover voice, 1=lfo, 2=predelay, 3=predrive, 4=main)

### Global Parameters

#### Cross-Modulation 

- `mod_depth` (0-1)
- `routing`

Voice pairs: 1-2, 3-4, 5-6, 7-8

**Self (0)**: 1 ↔ 2, 3 ↔ 4, 5 ↔ 6, 7 ↔ 8, 
**Neighbor (1)**: 1-2 ↔ 3-4, 5-6 ↔ 7-8  
**Cross (2)**: 1-2 ↔ 5-6, 3-4 ↔ 7-8  
**Loop (3)**: 1-2 → 3-4 → 5-6 → 7-8 → 1-2

### LFO Modes

- freqA
- freqB
- style

- **Single (0)**: Use freqA only
- **Sum (1)**: freqA + freqB
- **Product (2)**: freqA × freqB
- **FM (3)**: Soft frequency modulation

### Delay Parameters

- `delay_time` - Two taps times (0-2 seconds)
- `delay_mod` - Two taps modulation depth
- `delay_fb` - Feedback amount (0-1)
- `delay_mix` - Dry/wet mix (0-1)
- `delay_mod` - Modulation source (lfo/self)

### Distortion Parameters

- `distDrive` - Drive amount (1-11)
- `distMix` - Dry/wet mix (0-1)

## AI Disclosure

Claude.ai was used in the construction of this. However, the design was cleanroomed and completely human generated. Claude generated framework code, but did not assist in the formulation of ideas or design.
