#!/bin/bash

docker exec vuddy bash ./convert_signatureDB.sh VP-Bench_Test_Dataset/jasper
docker exec vuddy bash ./convert_signatureDB.sh RealVul_Dataset/jasper
docker exec vuddy python3 checker/check_clones.py --target output/VP-Bench_Test_Dataset/jasper/hidx/hashmark_4_jasper.hidx --database ./output/RealVul_Dataset/jasper/hidx/