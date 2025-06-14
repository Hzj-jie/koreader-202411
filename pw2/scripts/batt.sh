#!/bin/sh

grep Battery /var/log/messages | grep cycl | tail -n 1
