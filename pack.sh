#!/bin/bash

pushd linux ; tar -czhf ../linux.tar.gz . ; popd
pushd pw2 ; tar -czhf ../pw2.tar.gz . ; popd
pushd legacy ; tar -czhf ../legacy.tar.gz . ; popd
pushd kobo ; tar -czhf ../kobo.tar.gz . ; popd
