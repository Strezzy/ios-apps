"""Remove two redundant deconvolution output-shape arguments in a pinned model.

The published decoder's 2x2, stride-2, zero-pad deconvolutions have unambiguous
128x128 and 256x256 outputs. Explicit output_shape inputs prevent Core ML's
flexible prompt-token shape propagation on the tested runtime. All trained
weights, declared interfaces and other protobuf fields are preserved bytewise.
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


def text_field(data, field_number):
    found = [payload for number, wire, raw, payload in fields(data)
             if number == field_number and wire == 2]
    assert len(found) == 1
    return found[0].decode('utf-8')


changed = []


def operation(data):
    op_type = text_field(data, 1)
    if op_type != 'conv_transpose':
        # Operation.blocks (4) contains nested control-flow blocks, if any.
        return nested(data, 4, block)
    output = bytearray()
    keys = []
    removed = 0
    for number, wire, raw, payload in fields(data):
        if number == 2:
            assert wire == 2
            key = text_field(payload, 1)
            keys.append(key)
            if key == 'output_shape':
                removed += 1
                continue
        output.extend(raw)
    assert removed == 1
    assert set(keys) == {'bias', 'dilations', 'groups', 'output_shape', 'pad',
                         'pad_type', 'strides', 'weight', 'x'}, keys
    changed.append(op_type)
    return bytes(output)


def block(data):
    return nested(data, 3, operation)


def function(data):
    # Function.block_specializations map (3), map value (2).
    return nested(data, 3, lambda entry: nested(entry, 2, block))


def program(data):
    # Program.functions map (2), map value (2).
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
# Model.mlProgram is field 502. Unknown and unrelated fields are left untouched.
after = nested(before, 502, program)
assert len(changed) == 2 and len(after) < len(before)
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
            item['adaptation'] = 'Removed two redundant conv_transpose output_shape inputs; 2x2 kernels, stride 2, dilation 1 and zero padding preserve 128x128/256x256 outputs. Trained weights and interfaces unchanged.'
manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
script = Path('Loop/scripts/repair_sam_decoder.py')
script.write_text(Path(__file__).read_text())
research = Path('Loop/docs/CREATIVE-RESEARCH.md')
research.write_text(research.read_text()+'\n## SAM2 decoder runtime adaptation\nThe pinned Apple-converted decoder contains two optional, constant `conv_transpose.output_shape` inputs. The tested runtime failed flexible prompt-token shape propagation and returned flat masks. Loop removes those two redundant arguments; their 2x2 kernels, stride 2, dilation 1 and zero padding still determine the same 128x128 and 256x256 outputs. Weights, biases and public model interfaces are unchanged. The manifest records upstream and adapted specification checksums. The repair is reproducible in `scripts/repair_sam_decoder.py`; native tap and box-selection tests must pass before publication.\n')
print('Repaired SAM2 decoder specification:', original_sha, '->', hashlib.sha256(after).hexdigest(), '; trained weights unchanged')
