#!/usr/bin/python

import sys
import os.path
import errno
import argparse

try:
    from configparser import ConfigParser
except ImportError:
    from ConfigParser import ConfigParser  # ver. < 3.0



def print_vm_cmdline(config, vm_name):
    qvm_sects = config.sections()
    qvm_args=list()
    if vm_name in qvm_sects:
        qvm_args = config.items(vm_name)
        #skip ssh_user and ssh_append_options
        while 'qemu' != qvm_args[0][0]:
            qvm_args.pop(0) 
        #qemu type MUST be located first in VM section
        qemu_type = qvm_args[0][1]
        qvm_args.pop(0)
        print(qemu_type, end="")
        for qvm_a in qvm_args:
            print(" {}".format(qvm_a[1]), end='')
        print("")
        sys.exit(0)
    else:
        print("qVM %s doesn't exist in configfile" % vm_name);
        sys.exit(errno.ENOENT)

def print_available_vms(config):
   # for x in config.sections():
   #    if x != 'global':
   #       print(x)
    print( '\n'.join([ x for x in config.sections() if x != 'global' ]))
    sys.exit()

def print_value_by_vm_n_key(config, keys):
    vm_name = keys[0]
    key     = keys[1]
    value=""
    err=0
    try:
        value =  config[vm_name][key]
        print(value)
    except KeyError:
        print("No such keyvalue")
        err=errno.ENOENT
    sys.exit(err)

parser = argparse.ArgumentParser(description='Parse qVM config for constructing QEMU cmdline.')
#parser.add_argument('integers', metavar='N', type=int, nargs='+',
 #                   help='an integer for the accumulator')
#parser.add_argument('--sum', dest='accumulate', action='store_const',
#                    const=sum, default=max,
 #                   help='sum the integers (default: find the max)')
parser.add_argument('-l', '--list', action='store_true', help="list VMs from config file")
parser.add_argument('-g', '--get', nargs=1, metavar='qVM_name', help="construct QEMU cmdline from given VM name")
parser.add_argument('-s', '--set', nargs=1, metavar='qVM_name', help="save QEMU cmdline to new VM name as section")
parser.add_argument('-k', '--keyvalue',  nargs=2, help="get value by key of given VM, e.g. --keyvalue vm0 ssh_user", dest='keys')

args = parser.parse_args()
config = ConfigParser()
config.read(os.path.expanduser('~/.qvm.conf'))

if args.list:
    print_available_vms(config)
elif args.get:
    print_vm_cmdline(config, args.get[0])
elif args.keys:
    print_value_by_vm_n_key(config, args.keys)
#if len(sys.argv) > 2:
#    vm_name = sys.argv[1]
#else:
#    err=errno.ENOENT
#    print("Errno: {}\nNo VM name specified, exit".format(os.strerror(err)))
#    sys.exit(err);
# instantiate

# parse existing file

#print(qvm_sects)

#qvm_gl_dict = dict()

#for s in qvm_sects:
#   if s != 'global'
#        qvm_gl_dict[s] = config.items(s)

#print(qvm_gl_dict)
## read values from a section
#string_val = config.get('section_a', 'string_val')
#bool_val = config.getboolean('section_a', 'bool_val')
#int_val = config.getint('section_a', 'int_val')
#float_val = config.getfloat('section_a', 'pi_val')
#
## update existing value
#config.set('section_a', 'string_val', 'world')
#
## add a new section and some values
#config.add_section('section_b')
#config.set('section_b', 'meal_val', 'spam')
#config.set('section_b', 'not_found_val', '404')
#
## save to a file
#with open('test_update.ini', 'w') as configfile:
#    config.write(configfile)
