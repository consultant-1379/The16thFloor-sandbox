Run K6 test using the script 'run_k6_test.sh' as decribed here:
    run_k6_test.sh -s sso-limit-benchmark.js
or
    run_k6_test.sh -s sso-limit-benchmark.js -d

Run 'run_k6_test.sh -h' for usage info.

Or, to run the test manually without the launch script, see the example below:
    k6 run --quiet --verbose --log-output=file=sso-limit-benchmark-k6.log --console-output sso-limit-benchmark-console.log sso-limit-benchmark.js | tee sso-limit-benchmark-result.log
    docker run --rm -i grafana/k6 run - < sso-limit-benchmark.js > sso-limit-benchmark-k6.log
