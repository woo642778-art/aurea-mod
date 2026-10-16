import pathlib,struct,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from package_ipa import validate_dylib, safe_archive_name
class PackagingContract(unittest.TestCase):
    def fixture(self,platform=2):
        cmd=struct.pack('<6I',0x32,24,platform,0x100300,0x120500,0)
        return struct.pack('<8I',0xfeedfacf,0x100000c,0,6,1,len(cmd),0,0)+cmd
    def test_device_library(self):
        self.assertEqual(validate_dylib(self.fixture())['platform'],2)
    def test_simulator_rejected(self):
        with self.assertRaises(ValueError):validate_dylib(self.fixture(7))
    def test_corruption_rejected(self):
        for blob in (b'',self.fixture()[:-1],b'BAD!'+self.fixture()[4:]):
            with self.assertRaises(ValueError):validate_dylib(blob)
    def test_safe_paths(self):
        self.assertTrue(safe_archive_name('Payload/Aurea.app/Aurea'))
        self.assertTrue(safe_archive_name('Payload/'))
        for p in ('/absolute','../up','Payload/../up','Payload/./Aurea','Payload//Aurea','bad\\file'):
            self.assertFalse(safe_archive_name(p),p)
if __name__=='__main__':unittest.main()
