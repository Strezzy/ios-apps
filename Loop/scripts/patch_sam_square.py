"""Replace scalar pow(x, 2) with mul(x, x) in the bundled SAM mask decoder.

The transform is algebraically identical for real inputs. It avoids backend
power implementations whose negative-base path is not defined. No learned
parameters, prompt handling, dimensions or other graph operations are changed.
"""
from pathlib import Path
import hashlib
import json
import struct
import coremltools as ct

root = Path('Loop/Resources/SceneModels')
model_path = root / 'SAM2TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel'
weights = model_path.parent / 'weights/weight.bin'
weights_before = hashlib.sha256(weights.read_bytes()).hexdigest()
before = hashlib.sha256(model_path.read_bytes()).hexdigest()
spec = ct.utils.load_spec(str(model_path))
changes = []


def scalar_const(operation):
    assert operation.type == 'const'
    value = operation.attributes['val']
    tensor = value.immediateValue.tensor
    if tensor.floats.values:
        assert len(tensor.floats.values) == 1
        return float(tensor.floats.values[0])
    data = tensor.bytes.values
    assert len(data) == 2, str(value)
    return struct.unpack('<e', data)[0]


def transform(block, inherited=None):
    constants = dict(inherited or {})
    for operation in block.operations:
        if operation.type == 'const':
            for output in operation.outputs:
                constants[output.name] = operation
        if operation.type == 'pow':
            y = operation.inputs['y'].arguments
            assert len(y) == 1 and y[0].name in constants
            exponent = scalar_const(constants[y[0].name])
            assert exponent == 2.0, exponent
            source = operation.inputs['x']
            operation.type = 'mul'
            operation.inputs['y'].CopyFrom(source)
            changes.append({'output': operation.outputs[0].name,
                            'before': 'pow(x, 2)', 'after': 'mul(x, x)'})
        for nested in operation.blocks:
            transform(nested, constants)


for function in spec.mlProgram.functions.values():
    for block in function.block_specializations.values():
        transform(block)
assert len(changes) == 1, changes
model_path.write_bytes(spec.SerializeToString())
assert hashlib.sha256(weights.read_bytes()).hexdigest() == weights_before
result = {'model': 'SAM2TinyMaskDecoderFLOAT16', 'changes': changes,
          'upstreamGraphSHA256': before,
          'patchedGraphSHA256': hashlib.sha256(model_path.read_bytes()).hexdigest(),
          'unchangedWeightsSHA256': weights_before,
          'validation': 'Requires native rendering checks for this source commit.'}
manifest_path = root / 'SCENE-MODELS.json'
manifest = json.loads(manifest_path.read_text())
updated = 0
for model in manifest['models']:
    for entry in model['files']:
        if (root / entry['path']) == model_path:
            assert entry['sha256'] == before
            entry['upstreamSHA256'] = before
            entry['sha256'] = result['patchedGraphSHA256']
            model['localGraphTransform'] = result
            updated += 1
assert updated == 1
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(result, indent=2))
