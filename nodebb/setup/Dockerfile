FROM nodebb/docker:latest

# 1. העתקת התעודה
COPY ./netfree-ca.crt /etc/ssl/certs/netfree-ca.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/netfree-ca.crt

WORKDIR /usr/src/app

# 🌟 2. משנים את המשתמש ל-root רק לצורך ריצת ה-npm install
USER root

# 🌟 3. מעתיקים מראש את התוסף תחת הבעלות של node (חוסך chown עתידי)
COPY --chown=node:node ./nodebb/custom_plugins/nodebb-plugin-sso-oauth ./custom_plugins/nodebb-plugin-sso-oauth

# 🌟 4. מתקינים את התוסף ומעבירים את הדגל שמנטרל אזהרות מנוע
RUN npm install --no-engine-strict ./custom_plugins/nodebb-plugin-sso-oauth

# 🌟 5. מחזירים מיד למשתמש node הרגיל (בלי להריץ chown -R על כל האפליקציה!)
USER node