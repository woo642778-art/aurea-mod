import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HTTPSafety(unittest.TestCase):
    def test_production_validation(self):
        self.assertTrue((ROOT/'native/AUHTTP.c').exists(), 'Native HTTP range/path validation has not been implemented')
        with tempfile.TemporaryDirectory() as d:
            out=pathlib.Path(d)/'test-http'
            subprocess.run(['clang','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I'+str(ROOT/'native'),str(ROOT/'tests/test_http.c'),str(ROOT/'native/AUHTTP.c'),'-o',str(out)],check=True)
            subprocess.run([str(out)],check=True)
if __name__=='__main__':unittest.main()
