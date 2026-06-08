# 1. אומרים לדוקר בצורה מפורשת שהבסיס לאימג' הזה הוא NodeBB הרשמי
FROM nodebb/docker:latest

# 2. מעתיקים את תעודת נטפרי מתיקיית האב לתוך הלינוקס של הקונטיינר
COPY ./netfree-ca.crt /etc/ssl/certs/netfree-ca.crt

# 3. מגדירים את משתנה הסביבה שישמש את npm בזמן הבנייה
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/netfree-ca.crt

# 4. מתקינים את התוסף של קיקלוק באופן קשיח לתוך הליבה של האימג'!
RUN npm install nodebb-plugin-sso-oauth