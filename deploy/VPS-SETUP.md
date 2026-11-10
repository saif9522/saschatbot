# SAS Chatbot backend — BigRock VPS par setup

Database **Supabase par hi rahega**. Sirf backend (bot + API) Render se VPS par aayega.
Website (frontend) Vercel par hi rahegi. Naya address hoga: **https://api.saschatbot.com**

Kul samay: lagbhag 30–45 minute. Bot sirf 2–5 minute band rahega (step 4 ke dauraan).

---

## Step 0 — Taiyaari (10 minute)

1. **VPS ka root password / SSH access** BigRock panel se lijiye. VPS IP: `66.116.240.89`
2. **DNS record banaiye** — jahan `saschatbot.com` ka DNS hai (BigRock domain panel ya Vercel → Domains):
   - Type: **A**   Name/Host: **api**   Value: **66.116.240.89**   TTL: default
   - 5–30 minute me chalu ho jata hai. Check: `ping api.saschatbot.com` → 66.116.240.89 aana chahiye.
3. **Render se saari settings copy kariye**: Render → sarabot-backend → Environment → har value ke aage 👁️ dabakar
   ek notepad me copy kariye. Sabse zaroori: `SESSION_SECRET`, `DATABASE_URL`, `DIRECT_URL`, `OPENAI_API_KEY`.
   ⚠️ `SESSION_SECRET` **bilkul wahi** hona chahiye, warna WhatsApp number dobara link karna padega.
4. **cPanel hai ya nahi?** Agar VPS par cPanel/WHM hai, to cPanel → **Domains → Create a new domain** →
   `api.saschatbot.com` bana dijiye (document root kuch bhi). cPanel nahi hai to ye step chhod dijiye.

## Step 1 — Code VPS par laaiye (GitHub se — recommended)

**1a. Pehle code GitHub par daaliye** (apne computer par, VS Code Terminal me, backend folder ke andar —
zip ki files us folder me "Replace" karke):
```bash
git add -A
git commit -m "v12: VPS ready"
git push origin HEAD:main
```

**1b. GitHub token banaiye** (repo private hai, isliye VPS ko password jaisa ek token chahiye):
GitHub → photo → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
- Name: `bigrock-vps`, Expiration: 1 year
- Repository access: **Only select repositories → sarabot-backend**
- Permissions → Repository permissions → **Contents: Read-only**
- **Generate token** → token copy karke notepad me rakhiye (dobara nahi dikhega).

**1c. VPS par code laaiye** — SSH me (`ssh root@66.116.240.89`):
```bash
(command -v git || apt-get install -y git || dnf install -y git || yum install -y git)
id sasbot || useradd -m -s /bin/bash sasbot
sudo -u sasbot git -C /home/sasbot config --global credential.helper store
sudo -u sasbot git clone https://github.com/saif9522/sarabot-backend.git /home/sasbot/app
```
Username poochhe to: `saif9522`. Password poochhe to: **token paste kariye** (screen par kuch nahi dikhega, Enter dabaiye).
Token save ho jayega, aage update me dobara nahi poochhega.

> Doosra tareeka (bina GitHub): zip ko WinSCP se `/root` me daaliye, `unzip -o sarabot-backend-v12.zip`, aur Step 2 me
> `bash /root/sarabot-backend-main/deploy/vps-setup.sh` chalaiye.

## Step 2 — Pehla setup (Node 22, PM2, settings file)

```bash
bash /home/sasbot/app/deploy/vps-setup.sh
```
Ye Node 22 + PM2 install karega, `sasbot` naam ka user banayega, aur
settings file banakar rukega. Ab settings bhariye:

```bash
nano /home/sasbot/app/.env
```
Step 0 me copy ki hui values `=` ke baad paste kariye (Ctrl+O, Enter se save, Ctrl+X se bahar).
"Server" wali lines jaise hain waise rehne dijiye.

## Step 3 — Render band kariye ⚠️ (zaroori)

Ek WhatsApp number ko **ek hi server** chala sakta hai. Dono chale to WhatsApp disconnect hota rahega.
Render → sarabot-backend → **Settings → Suspend Web Service**. (Baad me zaroorat ho to "Resume" kar sakte hain.)

## Step 4 — Backend chalu kariye

```bash
bash /home/sasbot/app/deploy/vps-setup.sh
```
2–4 minute me build hoga aur aakhir me `{"ok":true,"build":"2026-11-10.12 …"}` dikhega.
**Bot ab VPS se WhatsApp par jawab dena shuru kar dega** (WhatsApp number same rehta hai, dobara link nahi karna).

## Step 5 — https://api.saschatbot.com chalu kariye (SSL ke saath)

```bash
bash /home/sasbot/app/deploy/proxy-setup.sh api.saschatbot.com aapka@email.com
```
- cPanel ho to Apache + AutoSSL, warna Nginx + Let's Encrypt — script khud pehchan lega.
- Aakhir me `Done! Backend is live at https://api.saschatbot.com/api` aana chahiye.
- Browser me check: **https://api.saschatbot.com/api/health**

## Step 6 — Website ko naye address se jodiye (Vercel)

Vercel → sarabot-frontned → **Settings → Environment Variables**:
- `NEXT_PUBLIC_API_URL` = `https://api.saschatbot.com/api`
- `NEXT_PUBLIC_WS_URL` agar bana hai to = `https://api.saschatbot.com` (ya use delete kar dijiye)

Phir **Deployments → sabse upar wale deploy ke ⋯ → Redeploy**. Ready hone ke baad saschatbot.com par
**dobara login** kariye (naye server ke liye naya login lagta hai).

## Step 7 — Razorpay (agar payment chalu hai)

Razorpay Dashboard → Webhooks → URL badaliye: `https://api.saschatbot.com/api/payments/webhook`

---

## Roz ke kaam

| Kaam | Command (SSH me) |
|---|---|
| Live logs dekhna | `sudo -u sasbot pm2 logs sas-chatbot` |
| Status | `sudo -u sasbot pm2 status` |
| Restart | `sudo -u sasbot pm2 restart sas-chatbot` |
| Naya code (GitHub se) | pehle computer se GitHub par push, phir VPS par: `sudo -u sasbot bash /home/sasbot/app/deploy/update.sh` |
| Settings badli (.env) | `nano /home/sasbot/app/.env` → `sudo -u sasbot pm2 restart sas-chatbot --update-env` |

## Dikkat aaye to

- **Build fail / app start nahi hua**: `sudo -u sasbot pm2 logs sas-chatbot --lines 80` ka output bhejiye.
- **`SESSION_SECRET ... is empty`**: .env me Render wala SESSION_SECRET daaliye.
- **`has no DNS record yet`**: Step 0 ka A record banaiye aur 15–30 minute rukiye.
- **Dashboard login nahi ho raha**: Step 6 ke baad Redeploy hua ya nahi, aur browser me ek baar logout/login.
- **Wapas Render par jaana ho**: VPS par `sudo -u sasbot pm2 stop sas-chatbot`, Render me Resume,
  Vercel me `NEXT_PUBLIC_API_URL` purana (`https://sarabot-backend.onrender.com/api`) karke Redeploy.
