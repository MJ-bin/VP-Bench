#!/bin/bash

# Create result directory if it doesn't exist
mkdir -p ./experiment/result/vuddy/
docker exec vuddy bash -c 'rm -rf /app/vuddy/output'

time docker exec vuddy bash ./convert_signatureDB.sh VP-Bench_Test_Dataset on \
 && echo "VP-Bench_Test_Dataset signature DB conversion completed."

time docker exec vuddy bash ./convert_signatureDB.sh VP-Bench_Train_Dataset on \
 && echo "VP-Bench_Train_Dataset signature DB conversion completed."

# Run the command and save output to host
time docker exec vuddy python3 checker/check_clones.py --target output/VP-Bench_Test_Dataset/hidx/hashmark_4_VP-Bench_Test_Dataset.hidx --database ./output/VP-Bench_Train_Dataset/hidx/ > ./experiment/result/vuddy/vuddy_result.txt \
&& echo "Vuddy experiment run completed."