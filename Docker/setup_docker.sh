mkdir /home/s4115;cd /home/s4115;wget http://www.cs.columbia.edu/~sedwards/classes/2016/4115-summer/microc-llvm.tar.gz;tar xvzf microc-llvm.tar.gz;cd microc-llvm/;sudo apt-get update;sudo apt-get -y install software-properties-common python-software-properties software-properties-common python-software-properties m4; sudo add-apt-repository 'deb http://llvm.org/apt/trusty/ llvm-toolchain-trusty-3.7 main';wget -O - http://llvm.org/apt/llvm-snapshot.gpg.key | sudo apt-key add;sudo apt-get -y install llvm-3.7-dev; opam init; opam depext conf-pkg-config.1.0; opam install llvm.3.7 ocamlfind;eval `opam config env`;make
