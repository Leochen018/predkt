import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';

export default function VerifyPage() {
  const router = useRouter();
  const { token, userId } = router.query;
  const [status, setStatus] = useState('Verifying your account...');

  useEffect(() => {
    // Only run if the URL has the token and userId
    if (token && userId) {
      const verifyEmail = async () => {
        try {
          const res = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/verify-email`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token, userId })
          });
          const data = await res.json();

          if (data.ok) {
            setStatus('✅ Email Verified! Redirecting to login...');
            setTimeout(() => router.push('/'), 3000);
          } else {
            setStatus(`❌ Verification failed: ${data.error || 'Unknown error'}`);
          }
        } catch (err) {
          setStatus('❌ Connection error. Please try again later.');
        }
      };
      verifyEmail();
    }
  }, [token, userId, router]);

  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh', fontFamily: 'sans-serif' }}>
      <div style={{ textAlign: 'center', padding: '20px', border: '1px solid #ddd', borderRadius: '8px' }}>
        <h2>{status}</h2>
        {!token && <p>Waiting for verification details...</p>}
      </div>
    </div>
  );
}