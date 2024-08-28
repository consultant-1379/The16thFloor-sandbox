/*
   SSO Burst Benchmark testing script. 
   It is intended to verify handling of 50 auth/sec burst

   load pattern applied (in minutes):

      _ _ _ _ 
     /       \
    /         \
   /           \__________________

   | 1|  2  | 1|        10        |

*/


import http from 'k6/http';
import { sleep, check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';


let stages = [

      // Linearly ramp-up to 20 iterations (from startRate) per `timeUnit` over the following minute.
      { target: 50, duration: '1m' },

      // Continue starting 20 iterations per `timeUnit` for the following three minutes.
      { target: 50, duration: '2m' },

      // Linearly ramp-down to starting 5 iterations per `timeUnit` over the following minute.
      { target: 15, duration: '1m' },

      // Continue starting 5 iterations per `timeUnit` for the following ten minutes.
      { target: 15, duration: '11m' }

    ];


let final_stages = [];

// total duration: 15*16= 4h
for (let i = 0 ;i < 16; i++) {
    final_stages = final_stages.concat(stages)
}

export const options = {
    insecureSkipTLSVerify: true,
    scenarios: {
      const_rate_sc: {
        // starts a fixed number of iterations over a specified period of time
        executor: 'ramping-arrival-rate',

        // function to exec
        exec: 'login_logout',

        // Start iterations per `timeUnit`
        startRate: 15,

        // Start `rate` iterations per second
        timeUnit: '1s',

        // Pre-allocate VUs
        preAllocatedVUs: 500,

        stages: final_stages,
      },
    },
};


export function handleSummary(data) {
  let summary = textSummary(data, { indent: ' ', enableColors: true })
  return {
    'stdout': summary,
    'summary.log': summary,
  };
}

//change server_url with proper one
const server_url = 'https://enmapache.athtem.eei.ericsson.se';

const login_url = server_url + '/login';
const logout_url = server_url + '/logout';
const payload = 'IDToken1=administrator&IDToken2=TestPassw0rd';

export function login_logout() {

  // cookies are automatically handled by k6, stored in login and passed along in logout
  let res = http.post(login_url, payload, {headers: {'Content-Type': 'application/x-www-form-login_urlencoded'}, redirects: 0});
  if (!check(res, {
    'login req has status 302': (r) => r.status == 302,
    "login sets cookie 'iPlanetDirectoryPro'": (r) => r.cookies.iPlanetDirectoryPro[0] !== null,
    })
  ) {
    console.log("Failed checks during login. Response status: " + res.status + ", Response json: " + JSON.stringify(res.json()));
  }
  sleep(0.1)

  res = http.get(logout_url)
  if (!check(res, {
    'logout has status 200': (r) => r.status == 200,
    })
  ) {
    console.log("Failed checks during logout. Response status: " + res.status + ", Response json: " + JSON.stringify(res.json()));
  }
}