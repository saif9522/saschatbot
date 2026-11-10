/**
 * PM2 config for a VPS. Keeps the backend running 24x7 and restarts it if it crashes or the server reboots.
 *   pm2 start deploy/ecosystem.config.js     (first time)
 *   pm2 reload sas-chatbot                    (after an update)
 *   pm2 logs sas-chatbot                      (live logs)
 */
const path = require('path');
const app = path.resolve(__dirname, '..');

module.exports = {
  apps: [
    {
      name: 'sas-chatbot',
      cwd: app,
      script: 'dist/main.js',
      // Node 22 reads .env before any code runs (storage paths, secrets, database URL …).
      node_args: '--env-file=.env',
      // ONE process only: two copies would both connect the same WhatsApp numbers and fight.
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 20,
      restart_delay: 5000,
      max_memory_restart: '1500M',
      kill_timeout: 15000, // give WhatsApp time to close cleanly on restart
      time: true,
    },
  ],
};
