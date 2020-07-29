#!/usr/bin/env python3
import base64
import sys
import json
from os import path

# Use jtm tool to convert XML to json
# https://github.com/ldn-softdev/jtm
# And parse the json with this tool


def get_items_with_key(list_data, key_name):
    res = []
    for item in list_data:
        if key_name in item:
            res.append(item[key_name])
    return res


def log_error(msg):
    print(msg)


def decode_value(sms_value, encoding):
    if encoding == 'base64':
        return base64.b64decode(sms_value).decode("utf-8")
    else:
        log_error('Unknown encoding: ' + encoding)
        return sms_value


def to_file_name(address):
    address = address.lower()
    address = address.replace('+', '')
    address = address.replace(' ', '')
    address = address.replace('-', '')
    address = address.replace('&gt;', '')
    address = address.replace('&lt;', '')
    if address.find('08') == 0:
        address = '359' + address[1:]
    return address + '.json'


def load_or_init_address(address, dst_dir):
    address_file_name = to_file_name(address)
    file_path = path.join(dst_dir['dir'], address_file_name)
    if path.exists(file_path):
        with open(file_path) as file_path_fd:
            data = json.load(file_path_fd)
    else:
        data = []
    dst_dir['files'][address] = data
    return data


def unique_sent(address_data, date, sms_value):
    for item in address_data:
        if item['type'] == 'sent' and item['date'] == date and item['msg'] == sms_value:
            return False
    return True


def add_sent(address_data, date, sms_value):
    if unique_sent(address_data, date, sms_value):
        address_data.append({'type': 'sent', 'date': date, 'msg': sms_value})


def unique_recv(address_data, date, date_sent, sms_value):
    for item in address_data:
        if item['type'] == 'recv' and item['date'] == date and \
                item['dateSent'] == date_sent and item['msg'] == sms_value:
            return False
    return True


def add_inbox(address_data, date, date_sent, sms_value):
    if unique_recv(address_data, date, date_sent, sms_value):
        address_data.append({'type': 'recv', 'date': date, 'dateSent': date_sent, 'msg': sms_value})


def add_sms(sms_attributes, sms_value, dst_dir):
    address = sms_attributes['address']
    date = sms_attributes['date']
    date_sent = sms_attributes['dateSent'] if 'dateSent' in sms_attributes else None
    encoding = sms_attributes['encoding']
    msg_box = sms_attributes['msgBox']

    if encoding != 'plain':
        sms_value = decode_value(sms_value, encoding)

    address_data = dst_dir['files'][address] if address in dst_dir['files'] \
        else load_or_init_address(address, dst_dir)

    if msg_box == 'sent':
        add_sent(address_data, date, sms_value)
    elif msg_box == 'inbox':
        add_inbox(address_data, date, date_sent, sms_value)
    else:
        log_error('Unknown msgBox: ' + msg_box)


def process_json_data(threads, dst_dir):
    for thread in threads:
        thread_item = thread['thread'] if 'thread' in thread else None
        if thread_item is None:
            if 'attributes' not in thread:
                log_error('Unknown thread: ' + str(thread))
            continue
        sms_items = get_items_with_key(thread_item, 'sms')
        if sms_items is []:
            log_error('Unsupported thread: ' + str(thread))
            continue
        for sms_item in sms_items:
            sms_attributes = get_items_with_key(sms_item, 'attributes')[0]
            try:
                sms_value = sms_item[1]
            except IndexError:
                sms_value = ''
            add_sms(sms_attributes, sms_value, dst_dir)


def extract_sms_info(json_file, dst_dir):
    with open(json_file) as json_fd:
        json_data = json.load(json_fd)
        process_json_data(get_items_with_key(json_data, 'threads')[0], dst_dir)


def sort_data_key(item):
    return item['date'] if 'date' in item else ''


def sort_data(data):
    data.sort(key=sort_data_key)
    return data


def save_files(dst_dir):
    for key in dst_dir['files'].keys():
        address_file_name = to_file_name(key)
        file_path = path.join(dst_dir['dir'], address_file_name)
        data = dst_dir['files'][key]
        data = sort_data(data)
        with open(file_path, 'w', encoding='utf8') as file_path_fd:
            json.dump(data, file_path_fd, ensure_ascii=False)


if __name__ == '__main__':
    json_file = sys.argv[1]
    dst_dir = {'dir': sys.argv[2], 'files': {}}
    extract_sms_info(json_file, dst_dir)
    save_files(dst_dir)
