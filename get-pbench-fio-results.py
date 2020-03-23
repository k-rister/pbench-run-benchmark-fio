#!/bin/python

from __future__ import print_function

import json
import argparse
import re
import copy
import traceback
import urllib3


class t_global(object):
     args = None
     counter = -1
     data = []


def not_json_serializable(obj):
    try:
        return(obj.to_dictionary())
    except AttributeError:
        try:
            return("scapy:%s" % (obj.command()))
        except AttributeError:
            return(repr(obj))


def dump_json_readable(obj):
     return json.dumps(obj, indent = 4, separators=(',', ': '), sort_keys = True, default = not_json_serializable)


def dump_json_parsable(obj):
     return json.dumps(obj, separators=(',', ':'), default = not_json_serializable)


def process_options():
     parser = argparse.ArgumentParser(description = 'Load a pbench generated result.json and remove (trim) the timeseries data to reduce the file size.')

     parser.add_argument('--input',
                         dest = 'input',
                         help = 'JSON file to use as input',
                         default = ""
                    )
     parser.add_argument('--long',
                         dest = 'long_output',
                         help = 'Print output in long format rather than compact',
                         action = 'store_true'
                    )

     t_global.args = parser.parse_args();

     return()


def find_results(input_json):
     if type(input_json) is dict:
          walk_dict(input_json)
     elif type(input_json) is list:
          walk_list(input_json)


def walk_list(node):
     for index in range(0, len(node)):
          if type(node[index]) is dict:
               walk_dict(node[index])
          elif type(node[index]) is list:
               walk_list(node[index])


def walk_dict(node):
     for key in node.keys():
          if type(node[key]) is dict:
               if key == 'parameters':
                    gather_parameters(node[key])
                    continue
               elif key == 'iteration_data':
                    t_global.counter += 1
                    init_data_point()

               if key == 'iteration_data' or key == 'throughput':
                    walk_dict(node[key])
          elif type(node[key]) is list:
               if key == 'iops_sec':
                    gather_data(node[key])
               else:
                    walk_list(node[key])

     return(0)


def gather_parameters(node):
     for key in node.keys():
          if key == 'benchmark':
               gather_parameters(node[key][0])
          elif key == 'bs':
               fill_data_point(key, int(node[key].split('k')[0]))
          elif key == 'iodepth':
               fill_data_point(key, int(node[key]))
          elif key == 'filename':
               fill_data_point('files', node[key].split(','))
          

def gather_data(node):
     for index in range(0, len(node)):
          if node[index]['client_hostname'] == 'all':
               fill_data_point('iops', node[index]['mean'])
               fill_data_point('stddevpct', node[index]['stddevpct']/100.0)
               fill_data_point('stddev', node[index]['stddev'])
          else:
               increment_data_point('job_count')
               append_data_point('job_iops', node[index]['mean'])
               append_data_point('job_stddevpct', node[index]['stddevpct']/100.0)
               append_data_point('job_stddev', node[index]['stddev'])


def init_data_point():
     t_global.data.insert(t_global.counter, { 'bs': None,
                                              'iodepth': 1,
                                              'iops': None,
                                              'stddevpct': None,
                                              'stddev': None,
                                              'files': None,
                                              'calculated_job_count': None,
                                              'job_count': 0,
                                              'job_iops': [],
                                              'job_stddevpct': [],
                                              'job_stddev': [] })


def fill_data_point(key, value):
     t_global.data[t_global.counter][key] = value


def increment_data_point(key, value=1):
     t_global.data[t_global.counter][key] += value


def append_data_point(key, value):
     t_global.data[t_global.counter][key].append(value)


def get_block_sizes():
     blocks = []

     for record in t_global.data:
          if record['bs'] is not None:
               blocks.append(record['bs'])

     blocks = list(set(blocks))
     blocks.sort()

     return(blocks)


def get_iodepths():
     iodepths = []

     for record in t_global.data:
          if record['iodepth'] is not None and record['files'] is not None and record['calculated_job_count'] > 0:
               real_iodepth = record['iodepth'] * record['calculated_job_count']

               iodepths.append(real_iodepth)

               record['calculated_iodepth'] = real_iodepth

     iodepths = list(set(iodepths))
     iodepths.sort()

     return(iodepths)


def get_jobs():
     jobs = []

     for record in t_global.data:
          if record['files'] is not None and record['job_count'] > 0:
               unique_files = list(set(record['files']))
               job_count = record['job_count'] / len(unique_files)

               jobs.append(job_count)

               record['calculated_job_count'] = job_count

     jobs = list(set(jobs))
     jobs.sort()

     return(jobs)


def dump_result_matrix(block_sizes, iodepths, jobs):
     if t_global.args.long_output:
          print("\nBlock Sizes (inner loop):")
     else:
          print("\nBlock Sizes (rows):")
     print(dump_json_readable(block_sizes))

     if t_global.args.long_output:
          print("\nIO Depths (outer loop):")
     else:
          print("\nIO Depths (columns):")
     print(dump_json_readable(iodepths))

     print()

     dumps = [ 'iops', 'stddevpct' ]
     for dump in dumps:
          print('%s:' % (dump))
          string = ""

          if t_global.args.long_output:
               string = ""

               for iodepth in iodepths:
                    for block_size in block_sizes:
                         for record in t_global.data:
                              if record['calculated_iodepth'] == iodepth and record['bs'] == block_size:
                                   string = "%s%s;" % (string, record[dump])

               string = re.sub(r';$', '', string)
               print(string)
               print()
          else:
               for block_size in block_sizes:
                    string = ""

                    for iodepth in iodepths:
                         for record in t_global.data:
                              if record['calculated_iodepth'] == iodepth and record['bs'] == block_size:
                                   #string = "%s%s-%s-%s;" % (string, block_size, iodepth, record[dump])
                                   string = "%s%s;" % (string, record[dump])

                    string = re.sub(r';$', '', string)
                    print(string)
               print()


def main():
     process_options()

     m = re.search(r"http://", t_global.args.input)
     if m:
          try:
               http = urllib3.PoolManager()
               req = http.request('GET', t_global.args.input)
               input_json = json.loads(req.data.decode('utf-8'))

          except:
               print("Couldn't load input file %s" % (t_global.args.input))
               print(traceback.format_exc())
               return(1)
     else:
          try:
               input_fp = open(t_global.args.input, 'r')
               input_json = json.load(input_fp)
               input_fp.close()

          except:
               print("Couldn't load input file %s" % (t_global.args.input))
               return(1)

     find_results(input_json)

     #print(dump_json_readable(t_global.data))

     block_sizes = get_block_sizes()
     #print("Block Sizes")
     #print(dump_json_readable(block_sizes))

     jobs = get_jobs()
     #print("Jobs")
     #print(dump_json_readable(jobs))

     iodepths = get_iodepths()
     #print("IO Depths")
     #print(dump_json_readable(iodepths))

     #print(dump_json_readable(t_global.data))

     dump_result_matrix(block_sizes, iodepths, jobs)

     return(0)


if __name__ == "__main__":
     exit(main())
