"""Curbside brag soundtrack: 22 s, 120 BPM, F major (F C Dm Bb), SFX in key. Writes audio.wav."""
import sys, wave
import numpy as np

SR = 44100
DUR = 22.0
N = int(SR * DUR)
BEAT = 0.5
rng = np.random.default_rng(7)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)
def t_(d): return np.arange(int(SR * d)) / SR

L = np.zeros(N); R = np.zeros(N)
def add(sig, start, gain=1.0, pan=0.0, bus=None):
    i = int(start * SR)
    if i >= N: return
    sig = sig[: N - i] * gain
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    (bus or (L, R))[0][i:i + len(sig)] += sig * l * np.sqrt(2)
    (bus or (L, R))[1][i:i + len(sig)] += sig * r * np.sqrt(2)

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR); y = np.zeros_like(x); z = 0.0
    for i in range(len(x)):
        z = (1 - a) * x[i] + a * z; y[i] = z
    return y

# --- harmony: one chord per 2 s bar
CHORDS = [  # (bass root, pad voicing, arp tones)
    (41, [53, 57, 60, 67], [65, 69, 72, 77]),   # F (add9 colour on top)
    (36, [52, 55, 60, 64], [64, 67, 72, 76]),   # C
    (38, [50, 53, 57, 64], [62, 65, 69, 74]),   # Dm
    (34, [50, 53, 58, 65], [62, 65, 70, 74]),   # Bb
]
bars = int(np.ceil(DUR / 2))
last_bar_start = 19.2  # outro: hold F

# pads (dry bus + reverb bus)
padL = np.zeros(N); padR = np.zeros(N)
def pad_note(m, d):
    t = t_(d); f = hz(m)
    s = sum(a * (np.sin(2 * np.pi * f * k * (1 + det) * t)) for k, a in [(1, 1), (2, .35), (3, .12)] for det in (-.0015, .0015)) / 2
    env = np.minimum(1, t / .35) * np.minimum(1, (d - t) / .4)
    return s * env
for b in range(bars):
    st = b * 2.0
    if st >= last_bar_start: break
    d = min(2.0, last_bar_start - st) + .4
    for m in CHORDS[b % 4][1]:
        add(pad_note(m, d), st, .045, pan=(m % 5 - 2) * .15, bus=(padL, padR))
# outro chord: F add9, rings to the end
for m in [41, 53, 57, 60, 67, 72]:
    t = t_(DUR - last_bar_start); f = hz(m)
    s = (np.sin(2 * np.pi * f * t) + .3 * np.sin(4 * np.pi * f * t)) * np.minimum(1, t / .05) * np.exp(-t / 2.2)
    add(s, last_bar_start, .07 if m > 45 else .12, pan=(m % 5 - 2) * .15, bus=(padL, padR))

# plucks: 8th-note arpeggio
pl = np.zeros(N); pr_ = np.zeros(N)
ARP = [0, 1, 2, 3, 2, 1, 2, 3]
for b in range(bars):
    for k in range(16):
        st = b * 2.0 + k * .125 * 2 / 2 * 2  # 8ths = 0.25 s
        st = b * 2.0 + k * 0.25
        if k >= 8 or st >= last_bar_start - .01: continue
        m = CHORDS[b % 4][2][ARP[k]]
        d = .45; t = t_(d); f = hz(m)
        s = (np.sin(2 * np.pi * f * t) + .25 * np.sin(4 * np.pi * f * t) + .08 * np.sin(6 * np.pi * f * t)) * np.exp(-t / .16) * np.minimum(1, t / .004)
        g = .095 if st < 3.0 else .06
        add(s, st, g, pan=.35 if k % 2 else -.35, bus=(pl, pr_))

# bass (enters on the reveal)
for b in range(bars):
    for k, (off, dur) in enumerate([(0, .45), (1.0, .2), (1.5, .45)]):
        st = b * 2.0 + off
        if st < 3.0 or st >= 19.0: continue
        m = CHORDS[b % 4][0]; t = t_(dur); f = hz(m)
        s = np.tanh(1.6 * (np.sin(2 * np.pi * f * t) + .3 * np.sin(4 * np.pi * f * t))) * np.minimum(1, t / .01) * np.minimum(1, (dur - t) / .05)
        add(s, st, .16)

# drums
kick_env = np.zeros(N)
def kick():
    t = t_(.32); f = 45 + 75 * np.exp(-t / .045)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .11)
beat = 3.0
while beat < 19.0 - 1e-6:
    add(kick(), beat, .42)
    i = int(beat * SR); e = np.exp(-t_(.3) / .09); kick_env[i:i + len(e)] = np.maximum(kick_env[i:i + len(e)], e[: N - i])
    beat += BEAT
def hat():
    t = t_(.05); n = rng.standard_normal(len(t)); n = np.diff(np.concatenate([[0], n]))
    return n * np.exp(-t / .012)
def clap():
    t = t_(.18); n = rng.standard_normal(len(t))
    n = n - lowpass(n, 900)
    return (n * (np.exp(-t / .05)) + .3 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / .03))
x = 3.25
while x < 19.0:
    add(hat(), x, .045, pan=.3); x += .5
x = 3.5
while x < 19.0:
    add(clap(), x, .07, pan=-.05); x += 1.0

# sidechain the pad/plucks/bass a touch by the kick
duck = 1 - .35 * kick_env
padL *= duck; padR *= duck

# --- SFX (sit under the music)
def whoosh(d=.55):
    t = t_(d); n = rng.standard_normal(len(t))
    env = (t / d) ** 2.2 * np.minimum(1, (d - t) / .04)
    return lowpass(n, 2600) * env
for cut in [3.0, 6.0, 9.5, 13.5, 16.2, 19.2]:
    add(whoosh(), cut - .55, .09, pan=-.2 if cut % 2 else .2)

def bell(ms, d=1.6):
    t = t_(d); s = 0
    for m in ms:
        f = hz(m)
        s = s + (np.sin(2 * np.pi * f * t) + .25 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / .15)) * np.exp(-t / .55)
    return s * np.minimum(1, t / .003) / len(ms)
add(bell([77, 84]), 4.95, .13)             # gauge lands on 84 (F5 + C6)
add(bell([81, 89]), 10.85, .13)            # drive ring lands on 92 (A5 + F6)
add(bell([84]), 13.75, .07, pan=.2)        # offer card
add(bell([72, 77]), 17.05, .07, pan=-.2)   # family goal

t = t_(1.6)
boom = np.sin(2 * np.pi * 43.65 * t) * np.exp(-t / .5) * np.minimum(1, t / .01)
add(boom, 19.2, .35)

# --- reverb on pads + plucks + bells (simple convolution)
irt = t_(1.4); ir = rng.standard_normal(len(irt)) * np.exp(-irt / .35); ir[0] = 0
ir /= np.sqrt(np.sum(ir ** 2))
def conv(x):
    n = len(x) + len(ir); nf = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nf) * np.fft.rfft(ir, nf), nf)[: len(x)]
wetL = conv(padL + pl + .4 * L); wetR = conv(padR + pr_ + .4 * R)
L += padL + pl + .22 * wetL
R += padR + pr_ + .22 * wetR

# master: fade tail, soft clip, normalise to -1 dBFS
fade = np.ones(N); tail = int(1.3 * SR); fade[-tail:] = np.linspace(1, 0, tail) ** 1.5
fade[: int(.02 * SR)] = np.linspace(0, 1, int(.02 * SR))
mix = np.stack([L, R], 1) * fade[:, None]
mix = np.tanh(mix * 1.2) / 1.2
mix *= 10 ** (-1 / 20) / np.max(np.abs(mix))
out = sys.argv[1] if len(sys.argv) > 1 else 'audio.wav'
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype('<i2').tobytes())
rms = np.sqrt(np.mean(mix ** 2)); print('wrote', out, 'rms dBFS %.1f' % (20 * np.log10(rms)))
