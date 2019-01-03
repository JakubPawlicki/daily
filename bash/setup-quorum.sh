#apt-cache show $(xsel -b) | grep ^Description-en | tee /dev/fd/2 | cut -d':' -f2 | xsel -b
sudo apt-get install xterm jq git  -y
sudo apt-get install libdb-dev -y      #Description-en: Berkeley Database Libraries [development]
sudo apt-get install libleveldb-dev -y #fast key-value storage library (development files)
sudo apt-get install libsodium-dev -y  #Network communication, cryptography and signaturing library - headers
sudo apt-get install zlib1g-dev -y     #Compression library - development
sudo apt-get install libtinfo-dev -y   #developer's library for the low-level terminfo library

BASEDIR=$PWD
RAFT=$BASEDIR/raft
mkdir $RAFT

#https://tecadmin.net/install-go-on-ubuntu/
wget https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz
sudo tar -xvf go1.10.3.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo mv go /usr/local/

echo export GOROOT=/usr/local/go | sudo tee -a /etc/profile | sh
echo export PATH=$GOROOT/bin:$PATH | sudo tee -a /etc/profile | sh

cd $BASEDIR
git clone https://github.com/jpmorganchase/quorum.git
cd $BASEDIR/quorum
make all

#install constellation
cd $BASEDIR
curl -sSL https://get.haskellstack.org/ | sh
stack setup

cd $BASEDIR
git clone https://github.com/jpmorganchase/constellation.git
cd cd $BASEDIR/constellation
stack install

cp ~/.local/bin/constellation-node $RAFT/
cp $BASEDIR/quorum/build/bin/geth $RAFT/
cp $BASEDIR/quorum/build/bin/bootnode $RAFT/

cd $RAFT
yes "" | ./constellation-node --generatekeys=cnode1
yes "" | ./constellation-node --generatekeys=cnode2
yes "" | ./constellation-node --generatekeys=cnode3
yes "" | ./constellation-node --generatekeys=cnode4

declare -a OTHER=(2 3 4)
declare -a BROADCAST=(1)

cd $BASEDIR
for n in {1..4}; do
  if [ "$n" -eq "1" ]; then
    OTHERNODES=$(echo [$(printf ", \"http://127.0.0.1:900%s/\"" "${OTHER[@]}")] | sed 's/, //')
  else
    OTHERNODES=$(echo [$(printf ", \"http://127.0.0.1:900%s/\"" "${BROADCAST[@]}")] | sed 's/, //')
  fi
cat > $RAFT/constellation$n.conf <<EOF
url = "http://127.0.0.1:900$n/"
port = 900$n
storage = "dir:$RAFT/cnode_data/cnode$n/"
socket = "$RAFT/cnode_data/cnode$n/constellation_node$n.ipc"
othernodes = $OTHERNODES
publickeys = ["$RAFT/cnode$n.pub"]
privatekeys = ["$RAFT/cnode$n.key"]
tls = "off"
verbosity = 3
EOF
done

for n in {1..4}
do xterm -fg white -bg black -e "$RAFT/constellation-node $RAFT/constellation$n.conf" &
done

for n in {1..4}
do $RAFT/bootnode -genkey $BASEDIR/enode_id_$n #| tee /dev/fd/2 | sh
done

echo [ > $BASEDIR/static-nodes.json
for n in {1..4}
do  echo ===================================
    cat $BASEDIR/enode_id_$n
    echo
    echo \"enode://$($RAFT/bootnode -nodekey $BASEDIR/enode_id_$n -writeaddress)@127.0.0.1:2300$n?raftport=2100$n\" | tee -a $BASEDIR/static-nodes.json
    echo , >> $BASEDIR/static-nodes.json
done
CONTENT=$(head -n -1 $BASEDIR/static-nodes.json)]

for n in {1..4}
do echo ${CONTENT} > $RAFT/cnode_data/cnode$n/static-nodes.json
done

#create account
mkdir $RAFT/accounts
rm $RAFT/accounts/keystore/*
yes "" | $RAFT/geth --datadir $RAFT/accounts account new
ADDRESS=$(ls $RAFT/accounts/keystore | rev | cut -c 1-40 | rev)
mv $RAFT/accounts/keystore/* $RAFT/accounts/keystore/key1

#https://github.com/jpmorganchase/quorum-examples/blob/master/examples/7nodes/genesis.json
cat - | jq ".alloc = {\"0x$ADDRESS\":{\"balance\":\"1000000000000000000000000000\"}}" > $RAFT/genesis.json <<EOF
{
  "alloc": {},
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config": {
    "homesteadBlock": 0
  },
  "difficulty": "0x0",
  "extraData": "0x",
  "gasLimit": "0x7FFFFFFFFFFFFFFF",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00"
}
EOF

for n in {1..4}
do 
   echo ======================node $n
   QUORUM_NODE=$RAFT/cnode_data/cnode$n
   rm -rf $QUORUM_NODE/{keystore,geth}
   echo mkdir -p $QUORUM_NODE/{keystore,geth} | tee /dev/fd/2 | sh
   #echo cp $RAFT/genesis.json $QUORUM_NODE/  | tee /dev/fd/2 | sh
   echo cp $RAFT/accounts/keystore/key1 $QUORUM_NODE/keystore/  | tee /dev/fd/2 | sh
   echo cp $BASEDIR/enode_id_$n $QUORUM_NODE/geth/nodekey | tee /dev/fd/2 | sh
   echo $RAFT/geth --datadir $QUORUM_NODE init $RAFT/genesis.json | tee /dev/fd/2 | sh
done


for n in {1..4}
do 
   QUORUM_NODE=$RAFT/cnode_data/cnode$n   
   xterm -T "quorum geth $n" -fg white -bg black -e "cd $RAFT; PRIVATE_CONFIG=$RAFT/constellation$n.conf $RAFT/geth --verbosity 2 --datadir $QUORUM_NODE --port 2300$n --raftport 2100$n --raft --ipcpath \"$QUORUM_NODE/geth.ipc\"" &
   #cd $RAFT; PRIVATE_CONFIG=$RAFT/constellation$n.conf $RAFT/geth --verbosity 4 --datadir $QUORUM_NODE --port 2300$n --raftport 2100$n --raft --ipcpath "$QUORUM_NODE/geth.ipc"
done

cp $RAFT/accounts/keystore/* $QUORUM_NODE/keystore/
mist --rpc=$QUORUM_NODE/geth.ipc --gethpath=$RAFT/geth

f941a5bf5806bd5d2fce6c271e63e5a9e8927fe4

yes "" | $RAFT/geth --datadir $RAFT/accounts account new

Private key: 0x1f01c0930df479da4aec796d149c8be2620a745853f2c49e677000e558d42080
Public key:  9cb911d5d31cb966706d3764892ed2d4b7ed34cf6e7e4f365a260532e6aacc39d85ae652d62f6139a128a8da81c66531740228c9d8b29f94e5ed9efc31a764fd
Address:     0x3223f261cf7d8bb13a63a348cd40d32427399693

$RAFT/geth --datadir $RAFT/accounts account import <(echo 1f01c0930df479da4aec796d149c8be2620a745853f2c49e677000e558d42080)
$RAFT/geth --ipcpath=$QUORUM_NODE/geth.ipc --datadir $QUORUM_NODE attach

echo $QUORUM_NODE/geth.ipc
