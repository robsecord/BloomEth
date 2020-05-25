#!/usr/bin/env bash

# NOTE: Install "jq"
# brew install jq

requireFields='{fileName: .fileName, contractName: .contractName, abi: .abi, compiler: .compiler, networks: .networks}'

rm -f ./Bloom.json
rm -f ./BloomAaveBridge.json
rm -f ./BloomERC1155.json

echo "Generating JSON file for Bloom"
cat ./build/contracts/Bloom.json | jq -r "$requireFields" > ./Bloom.json

echo "Generating JSON file for BloomAaveBridge"
cat ./build/contracts/BloomAaveBridge.json | jq -r "$requireFields" > ./BloomAaveBridge.json

echo "Generating JSON file for BloomERC1155"
cat ./build/contracts/BloomERC1155.json | jq -r "$requireFields" > ./BloomERC1155.json


