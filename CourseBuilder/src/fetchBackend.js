// Read-only pull from Supabase backend for Pinch Brook course metadata.

const SUPABASE_URL  = 'https://aoxturoezgecwceudeef.supabase.co';
const SUPABASE_ANON = 'sb_publishable_Qk0gdBkqnTb2PV2bEfW-3A_COWs5lOU';
const COURSE_ID     = '84c99a0e-46d1-592c-a717-be8aefc3ff79';

async function supabaseGet(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      apikey:        SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`,
      Accept:        'application/json',
    },
  });
  if (!res.ok) throw new Error(`Supabase ${res.status} on ${path}`);
  return res.json();
}

export async function fetchPinchbrookBackend() {
  console.log('  Fetching course metadata from backend…');
  const rows = await supabaseGet(`courses?id=eq.${COURSE_ID}&select=*`);
  if (!rows?.length) {
    console.warn('  Course not found in backend, using OSM/defaults');
    return {
      name: 'Pinch Brook Golf Course',
      city: 'Florham Park',
      state: 'NJ',
      country: 'US',
      lat: 40.793526,
      lng: -74.38804,
      holeCount: 18,
    };
  }
  const c = rows[0];
  return {
    name:      c.name || 'Pinch Brook Golf Course',
    city:      c.city || 'Florham Park',
    state:     c.state || 'NJ',
    country:   c.country || 'US',
    lat:       c.latitude  || 40.793526,
    lng:       c.longitude || -74.38804,
    holeCount: c.hole_count || 18,
  };
}
