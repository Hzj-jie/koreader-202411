#!/bin/bash

while true ; do
  date
  echo -n 'packets: '
  cat /sys/class/net/wlan0/statistics/tx_packets
  echo -n 'bytes: '
  cat /sys/class/net/wlan0/statistics/tx_bytes
  sleep 1m
done
