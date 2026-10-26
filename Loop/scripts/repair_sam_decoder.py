"""Apply equivalent runtime adaptations to one checksum-pinned SAM2 decoder.

The two 2x2, stride-2, zero-pad deconvolutions have unambiguous output sizes;
remove redundant output_shape inputs. Express the single pow(x,2) as mul(x,x)
to avoid negative-base backend power behavior. Trained weights are unchanged.
The bounded protobuf visitor preserves every unrelated wire field bytewise.
Schema: apple/coremltools mlmodel/format/{Model,MIL}.proto.
"""
from pathlib import Path
import hashlib
import json


def read_varint(data, pos):
    value = 0
    for shift in range(0, 70, 7):
        assert pos < len(data), 'Truncated protobuf varint'
        byte = data[pos]; pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
    raise AssertionError('Invalid protobuf varint')


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128); value >>= 7
    result.append(value)
    return bytes(result)


def fields(data):
    pos = 0
    while pos < len(data):
        start = pos
        tag, pos = read_varint(data, pos)
        number, wire = tag >> 3, tag & 7
        assert number > 0
        if wire == 0:
            _, end = read_varint(data, pos); payload = data[pos:end]
        elif wire == 1:
            end = pos + 8; payload = data[pos:end]
        elif wire == 2:
            length, pos = read_varint(data, pos)
            end = pos + length; payload = data[pos:end]
        elif wire == 5:
            end = pos + 4; payload = data[pos:end]
        else:
            raise AssertionError(('Unsupported wire type', wire))
        assert end <= len(data), 'Truncated protobuf field'
        yield number, wire, data[start:end], payload
        pos = end


def nested(data, field_number, function):
    output = bytearray()
    for number, wire, raw, payload in fields(data):
        if number == field_number:
            assert wire == 2
            edited = function(payload)
            output.extend(varint((number << 3) | 2) + varint(len(edited)) + edited)
        else:
            output.extend(raw)
    return bytes(output)


def payload_field(data, field_number):
    found = [payload for number, wire, raw, payload in fields(data)
             if number == field_number and wire == 2]
    assert len(found) == 1
    return found[0]


def text_field(data, field_number):
    return payload_field(data, field_number).decode('utf-8')


changed = []


def operation(data):
    op_type = text_field(data, 1)
    if op_type == 'pow':
        inputs = {text_field(p, 1): payload_field(p, 2)
                  for n, w, r, p in fields(data) if n == 2}
        assert set(inputs) == {'x', 'y'}
        # The checksum-pinned source has one square in its channel normalization.
        assert text_field(payload_field(inputs['y'], 1), 1) == 'var_978_promoted_to_fp16'
        assert text_field(payload_field(inputs['x'], 1), 1) == 'var_977_cast_fp16'
        edited = nested(data, 1, lambda _: b'mul')
        edited = nested(edited, 2, lambda entry: nested(entry, 2, lambda _: inputs['x'])
                        if text_field(entry, 1) == 'y' else entry)
        changed.append('pow(x,2) -> mul(x,x)')
        return edited
    if op_type != 'conv_transpose':
        return nested(data, 4, block)
    output = bytearray(); keys = []; removed = 0
    for number, wire, raw, payload in fields(data):
        if number == 2:
            assert wire == 2
            key = text_field(payload, 1); keys.append(key)
            if key == 'output_shape':
                removed += 1
                continue
        output.extend(raw)
    assert removed == 1
    assert set(keys) == {'bias', 'dilations', 'groups', 'output_shape', 'pad',
                         'pad_type', 'strides', 'weight', 'x'}, keys
    changed.append('conv_transpose output_shape removed')
    return bytes(output)


def block(data):
    return nested(data, 3, operation)


def function(data):
    return nested(data, 3, lambda entry: nested(entry, 2, block))


def program(data):
    return nested(data, 2, lambda entry: nested(entry, 2, function))


root = Path('Loop/Resources/SceneModels')
relative = 'SAM2TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel'
path = root / relative
before = path.read_bytes()
original_sha = hashlib.sha256(before).hexdigest()
assert original_sha == '24bd23b9267c8ccc172a5370bc3507d4e11f7a33ba14d529dfd904e7ebf50847'
weights = path.parent / 'weights/weight.bin'
weight_sha = hashlib.sha256(weights.read_bytes()).hexdigest()
assert weight_sha == '75d30eb00ad294872463b07efbfa17b536ae9ec4168f9b78f12a4fb57245ee94'
after = nested(before, 502, program)
assert changed.count('conv_transpose output_shape removed') == 2
assert changed.count('pow(x,2) -> mul(x,x)') == 1
assert len(after) < len(before)
path.write_bytes(after)
assert hashlib.sha256(weights.read_bytes()).hexdigest() == weight_sha
manifest_path = root / 'SCENE-MODELS.json'
manifest = json.loads(manifest_path.read_text())
for model in manifest['models']:
    for item in model['files']:
        if item['path'] == relative:
            item['upstreamSHA256'] = original_sha
            item['bytes'] = len(after)
            item['sha256'] = hashlib.sha256(after).hexdigest()
            item['localGraphChanges'] = changed
            item['unchangedWeightsSHA256'] = weight_sha
manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
Path('Loop/scripts/repair_sam_decoder.py').write_text(Path(__file__).read_text())
research = Path('Loop/docs/CREATIVE-RESEARCH.md')
research.write_text(research.read_text()+'\n## SAM2 decoder runtime adaptation\nThe pinned decoder has three equivalent local graph changes: its single `pow(x, 2)` uses `mul(x, x)` to avoid negative-base power behavior; two redundant `conv_transpose.output_shape` arguments are removed because 2x2 kernels, stride 2, dilation 1 and zero padding still determine the same 128x128/256x256 outputs. Learned weights and interfaces are unchanged. The manifest records upstream/adapted graph and weight checksums. `scripts/repair_sam_decoder.py` reproduces the changes. Native real-subject tap and box-selection tests gate publication. Nonfinite or flat masks are rejected, not replaced by a fabricated selection.\n')
p = Path('Loop/Core/Creative/SceneInference.swift')
s = p.read_text()
before_line = '            let f=array[indices].floatValue\n            let v=f.isFinite ? f:0'
after_line = '            let f=array[indices].floatValue\n            if logits && !f.isFinite {throw LoopError.encoding("The selection model returned invalid numerical values.")}\n            let v=f.isFinite ? f:0'
assert s.count(before_line) == 1
p.write_text(s.replace(before_line, after_line))
print('Adapted SAM2 decoder:', original_sha, '->', hashlib.sha256(after).hexdigest(), changed, '; weights unchanged')
