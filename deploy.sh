#!/usr/bin/env bash

# Parse env vars from .env file
export $(egrep -v '^#' .env | xargs)

nvm use

ownerAccount=
networkName="development"
silent=
update=

addrBloom=
addrBloomBridge=
addrBloomToken=

# Mainnet
# aaveProviderAddress="0x24a42fD28C976A61Df5D00D0599C34c4f90748c8"
# aaveDaiAddress="0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d"
# daiAddress="0x6b175474e89094c44da98b954eedeac495271d0f"

# Kovan
aaveProviderAddress="0x506B0B2CF20FAA8f38a4E2B524EE43e1f4458Cc5"
aaveDaiAddress="0x58AD4cB396411B691A9AAb6F74545b2C5217FE6a"
daiAddress="0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa"

depositFee="50000000000000000000"
daiPrefund="10000000000000000000"
createFeeEth="1100000000000000"
registerFeeEth="1100000000000000"
memberTokenUri="https://ipfs.io/ipfs/__todo__" # TODO

usage() {
    echo "usage: ./deploy.sh [[-n [development|ropsten|mainnet] [-i] [-u] [-v] [-s]] | [-h]]"
    echo "  -n    | --network [development|ropsten|mainnet]  Deploys contracts to the specified network (default is local)"
    echo "  -s    | --silent                                 Suppresses the Beep at the end of the script"
    echo "  -h    | --help                                   Displays this help screen"
}

echoHeader() {
    echo " "
    echo "-----------------------------------------------------------"
    echo "-----------------------------------------------------------"
}

echoBeep() {
    [[ -z "$silent" ]] && {
        afplay /System/Library/Sounds/Glass.aiff
    }
}

setOwnerSession() {
    if [[ "$networkName" == "development" ]]; then
        ownerAccount=$(oz accounts -n ${networkName} --no-interactive 2>&1 | head -n 9 | tail -n 1) # Get Account 3
        ownerAccount="${ownerAccount:(-42)}"
    elif [[ "$networkName" == "ropsten" ]]; then
        ownerAccount="$ROPSTEN_OWNER_ADDRESS"
    elif [[ "$networkName" == "mainnet" ]]; then
        ownerAccount="$MAINNET_OWNER_ADDRESS"
    fi
    oz session --no-interactive --from "$ownerAccount" -n "$networkName"
}

deployFresh() {
    setOwnerSession

    if [[ "$networkName" != "mainnet" ]]; then
        echoHeader
        echo "Clearing previous build..."
        rm -rf build/
        rm -f "./.openzeppelin/$networkName.json"
    fi

    echo "Compiling contracts.."
    oz compile

    echoHeader
    echo "Creating Contract: Bloom"
    oz add Bloom --push --skip-compile
    addrBloom=$(oz create Bloom --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: BloomAaveBridge"
    oz add BloomAaveBridge --push --skip-compile
    addrBloomBridge=$(oz create BloomAaveBridge --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: BloomERC1155"
    oz add BloomERC1155 --push --skip-compile
    addrBloomToken=$(oz create BloomERC1155 --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Contracts deployed.."

   echoHeader
   echo "Pre-funding owner with Asset Tokens.."

   echo " "
   echo "Pre-fund DAI: $daiPrefund"
   result=$(oz send-tx --no-interactive --to ${daiAddress} --method 'mint' --args ${ownerAccount},${daiPrefund})

    echoHeader
    echo "Initializing BloomERC1155.."

    echo " "
    echo "setBloomController: $addrBloom"
    result=$(oz send-tx --no-interactive --to ${addrBloomToken} --method 'setBloomController' --args ${addrBloom},'true')

    echoHeader
    echo "Initializing BloomAaveBridge.."

    echo " "
    echo "setDepositFee: $depositFee"
    result=$(oz send-tx --no-interactive --to ${addrBloomBridge} --method 'setDepositFee' --args ${depositFee})

    echo " "
    echo "setAddresses: $addrBloom,$aaveProviderAddress,$daiAddress,$aaveDaiAddress"
    result=$(oz send-tx --no-interactive --to ${addrBloomBridge} --method 'setAddresses' --args ${addrBloom},${aaveProviderAddress},${daiAddress},${aaveDaiAddress})

    echoHeader
    echo "Initializing Bloom.."

    echo " "
    echo "setupFees: $createFeeEth,$registerFeeEth"
    result=$(oz send-tx --no-interactive --to ${addrBloom} --method 'setupFees' --args ${createFeeEth},${registerFeeEth})

    echo " "
    echo "registerTokenBridge: $addrBloomBridge"
    result=$(oz send-tx --no-interactive --to ${addrBloom} --method 'registerTokenBridge' --args ${addrBloomBridge})

    echo " "
    echo "registerTokenManager: $addrBloomToken"
    result=$(oz send-tx --no-interactive --to ${addrBloom} --method 'registerTokenManager' --args ${addrBloomToken})

    echo " "
    echo "approveTokenBridge:"
    result=$(oz send-tx --no-interactive --to ${addrBloom} --method 'approveTokenBridge')

    echoHeader
    echo " "
    echo "MANUAL TODO:"
    echo "   oz send-tx -n $networkName --to $addrBloom"
    echo "    - createMembershipType: $memberTokenUri"

    echoHeader
    echo "Contracts initialized.."
    echo " "

    echoHeader
    echo "Contract Addresses: "
    echo " - Bloom:        $addrBloom"
    echo " - BloomBridge:  $addrBloomBridge"
    echo " - BloomERC1155: $addrBloomToken"

    echoHeader
    echo "Contract Deployment & Initialization Complete!"
    echo " "
    echoBeep
}


while [[ "$1" != "" ]]; do
    case $1 in
        -n | --network )        shift
                                networkName=$1
                                ;;
        -s | --silent )         silent="yes"
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

deployFresh
