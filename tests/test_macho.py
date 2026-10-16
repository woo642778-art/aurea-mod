"""Binary patch invariants, including the actual supplied unsigned executable when passed."""
import importlib.util, pathlib, struct, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class MachOPatch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=ROOT/'tools/patch_macho.py'
        if not path.exists(): raise AssertionError('Mach-O patch implementation does not exist')
        spec=importlib.util.spec_from_file_location('patch_macho',path)
        cls.mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.mod)
    def fixture(self):
        b=bytearray(8192)
        struct.pack_into('<8I',b,0,0xfeedfacf,0x100000c,0,2,1,152,0x200085,0)
        struct.pack_into('<II16sQQQQiiII',b,32,0x19,152,b'__TEXT',0x100000000,8192,0,8192,7,5,1,0)
        struct.pack_into('<16s16sQQIIIIIIII',b,104,b'__text',b'__TEXT',0x100001000,64,4096,2,0,0,0x80000400,0,0,0)
        b[4096:4160]=bytes(range(64));return bytes(b)
    def test_minimal_preserving_patch(self):
        raw=self.fixture();out,meta=self.mod.inject(raw)
        self.assertEqual(len(raw),len(out));self.assertEqual(out[4096:],raw[4096:]);self.assertEqual(out[32:184],raw[32:184]);self.assertEqual(struct.unpack_from('<I',out,16)[0],2);self.assertEqual(meta['command_offset'],184)
        commands=self.mod.commands(out);self.assertEqual(commands[-1]['cmd'],0x80000018);self.assertEqual(commands[-1]['name'],'@executable_path/Frameworks/AureaCraft.dylib')
        again,_=self.mod.inject(out);self.assertEqual(again,out)
    def test_refuse_encrypted_or_signed(self):
        for cmd,payload in [(0x2c,struct.pack('<IIII',4096,64,1,0)),(0x1d,struct.pack('<II',4096,64))]:
            b=bytearray(self.fixture());size=8+len(payload);struct.pack_into('<II',b,184,cmd,size);b[192:192+len(payload)]=payload;struct.pack_into('<II',b,16,2,152+size)
            with self.assertRaises(ValueError):self.mod.inject(bytes(b))
    def test_refuse_nonzero_padding(self):
        b=bytearray(self.fixture());b[190]=12
        with self.assertRaises(ValueError):self.mod.inject(bytes(b))
    def test_refuse_wrong_architecture_and_malformed(self):
        for raw in [b'abc',bytes(256)]:
            with self.assertRaises(ValueError):self.mod.inject(raw)
        b=bytearray(self.fixture());struct.pack_into('<I',b,4,0x1000007)
        with self.assertRaises(ValueError):self.mod.inject(bytes(b))
        b=bytearray(self.fixture());struct.pack_into('<I',b,36,0)
        with self.assertRaises(ValueError):self.mod.inject(bytes(b))
    def test_supplied_unsigned_executable(self):
        source=ROOT.parent/'original/Payload/Aurea.app/Aurea'
        if not source.exists():self.skipTest('Original application deliberately excluded from public CI')
        raw=source.read_bytes();out,meta=self.mod.inject(raw)
        self.assertEqual(meta['command_offset'],11640);self.assertEqual(meta['first_section'],16384)
        self.assertEqual(out[:16],raw[:16]);self.assertEqual(out[24:11640],raw[24:11640]);self.assertEqual(out[meta['command_offset']+meta['command_size']:],raw[meta['command_offset']+meta['command_size']:])
        self.assertEqual(len(raw),len(out))
if __name__=='__main__':unittest.main()
