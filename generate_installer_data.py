import argparse
import os
import sys

os_list = []
my_path = os.path.dirname(sys.argv[0])

parser = argparse.ArgumentParser(
    description="scan aosc asahi image file"
)

parser.add_argument("osname", metavar="OSNAME", type=str, help="Default OS Name")
args = parser.parse_args()
os_name = args.osname

for root, dirs, files in os.walk(f'{my_path}/build/'):
    for f in files:
        print(f)
        if f.endswith('.zip'):
            os = {}
            os['name'] = f.replace('.zip', '')
            os['default_os_name'] = os_name
            