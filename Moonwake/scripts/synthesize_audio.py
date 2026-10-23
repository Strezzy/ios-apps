#!/usr/bin/env python3
"""Compose Moonwake's original score and effects. No external recordings or downloads."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Resources' / 'Audio'
RATE = 22050
TAU = 2 * math.pi

def save(name, samples):
    peak = max(0.2, max(abs(v) for v in samples))
    scale = min(1, 0.88 / peak)
    data = array('h', (int(max(-1, min(1, s * scale)) * 32767) for s in samples))
    if sys.byteorder != 'little': data.byteswap()
    with wave.open(str(OUT / (name + '.wav')), 'wb') as file:
        file.setnchannels(1); file.setsampwidth(2); file.setframerate(RATE)
        file.writeframes(data.tobytes())

def freq(note): return 440 * 2 ** ((note - 69) / 12)

def note(buffer, start, duration, pitch, amp, voice='bell'):
    begin = int(start * RATE); length = int(duration * RATE); f = freq(pitch)
    for i in range(length):
        t = i / RATE; at = (begin + i) % len(buffer)
        if voice == 'pad':
            envelope = min(1, t / 0.8) * min(1, (duration - t) / 1.2)
            tone = (math.sin(TAU*f*t) + 0.33*math.sin(TAU*f*1.002*t) + 0.14*math.sin(TAU*f*2*t)) / 1.47
        elif voice == 'bass':
            envelope = min(1, t / 0.05) * math.exp(-t * 1.3) * min(1, (duration-t)/0.15)
            tone = math.sin(TAU*f*t) + 0.15*math.sin(TAU*f*2*t)
        else:
            envelope = min(1, t / 0.008) * math.exp(-t * 2.3) * min(1, (duration-t)/0.1)
            tone = math.sin(TAU*f*t) + 0.3*math.sin(TAU*f*2.003*t) * math.exp(-t*4)
        buffer[at] += tone * envelope * amp

def music(name, root, tempo, color, tension=False):
    beat = 60 / tempo; bar = beat*4; duration = bar*8
    samples = array('f', [0]) * int(duration*RATE)
    progression = [(0,3,7),(-5,-2,2),(-3,0,4),(-7,-4,0)]
    motif = [12, 19, 15, 14, 12, 10, 7, 10, 12, 15, 19, 22, 19, 15, 14, 10]
    for b in range(8):
        chord = progression[(b//2) % 4]
        for interval in chord:
            note(samples, b*bar, bar+1.6, root+interval, 0.042, 'pad')
        note(samples, b*bar, bar, root+chord[0]-12, 0.11, 'bass')
        for k in range(4 if tension else 2):
            p = root + motif[(b*2+k+color) % len(motif)]
            start = b*bar+k*(beat if tension else 2*beat)
            note(samples, start, 2.1, p, 0.095 if tension else 0.075)
            note(samples, start + beat*0.75, 1.5, p, 0.022)
        if tension:
            for k in range(4):
                note(samples, b*bar+k*beat, beat*0.8, root-12, 0.09, 'bass')
    # A loop-friendly low-level sea breath, periodic at the exact buffer length.
    rng=random.Random(823+color); filtered=0.0
    for i in range(len(samples)):
        filtered=filtered*0.96+(rng.random()*2-1)*0.04
        samples[i] += filtered*0.025*(0.6+0.4*math.sin(TAU*i/len(samples)*4))
    save(name, samples)

def effect(name, duration, kind):
    count=int(duration*RATE); data=array('f',[0])*count; rng=random.Random(72+kind)
    for i in range(count):
        t=i/RATE; u=i/max(1,count-1); env=math.sin(math.pi*u)**0.6
        noise=rng.random()*2-1
        if kind in (0,2):
            value=noise*0.18*env + math.sin(TAU*(800*t-500*t*t))*0.13*env
        elif kind in (1,6):
            value=(noise*0.16+math.sin(TAU*(160*t-60*t*t))*0.25)*math.exp(-12*t)
        elif kind==3:
            value=(math.sin(TAU*(130*t+400*t*t))*0.3+noise*0.05)*env
        elif kind in (4,5,8):
            notes=[69,76,81,84] if kind!=8 else [57,64,69,72,76,81]
            value=0
            for j,n in enumerate(notes):
                tt=t-j*duration/(len(notes)*1.6)
                if tt>=0: value+=math.sin(TAU*freq(n)*tt)*0.16*math.exp(-tt*4)*min(1,tt*100)
            value*=min(1,(duration-t)*12)
        elif kind==7:
            value=math.sin(TAU*(200*t-60*t*t))*0.3*env
        elif kind==9:
            value=math.sin(TAU*880*t)*0.12*env
        else: value=noise*0.03*math.exp(-t*50)
        data[i]=value
    save(name,data)

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    for row in [('moonshore',57,72,0),('briarwild',60,76,2),('glassmarsh',62,68,4),('ember',55,74,6),('eclipse',57,64,8),('guardian',57,108,10,True)]: music(*row)
    names=['sword','hit','dash','pulse','rune','reward','hurt','defeat','victory','menu','step']
    durations=[0.24,0.2,0.3,0.7,1.2,0.85,0.3,1.3,2.4,0.08,0.08]
    for i,(name,duration) in enumerate(zip(names,durations)): effect(name,duration,i)
    print(f'Composed {len(list(OUT.glob("*.wav")))} original audio assets.')
