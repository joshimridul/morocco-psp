# Pilot vertical linking

- Input file: `/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta`
- Linking method: concurrent single-factor calibration within subject using only vetted common items as shared columns.
- Final anchor rule: `usable_anchor` from the anchor audit, treated swing >-0.1, and at least 2 final anchors to sustain an adjacent-grade link.
- If an adjacent-grade link failed that threshold, the chain was broken rather than forced.

## Anchor edges

- Arabic g1-g2: 0 final anchors out of 0 usable candidates -> chain broken
- Arabic g2-g3: 2 final anchors out of 2 usable candidates -> kept as a link
- Arabic g3-g4: 7 final anchors out of 7 usable candidates -> kept as a link
- Arabic g4-g5: 3 final anchors out of 3 usable candidates -> kept as a link
- Arabic g5-g6: 2 final anchors out of 6 usable candidates -> kept as a link
- French g1-g2: 3 final anchors out of 3 usable candidates -> kept as a link
- French g2-g3: 23 final anchors out of 23 usable candidates -> kept as a link
- French g3-g4: 8 final anchors out of 8 usable candidates -> kept as a link
- French g4-g5: 9 final anchors out of 11 usable candidates -> kept as a link
- French g5-g6: 9 final anchors out of 9 usable candidates -> kept as a link
- Maths g1-g2: 1 final anchors out of 1 usable candidates -> chain broken
- Maths g2-g3: 3 final anchors out of 3 usable candidates -> kept as a link
- Maths g3-g4: 3 final anchors out of 5 usable candidates -> kept as a link
- Maths g4-g5: 4 final anchors out of 4 usable candidates -> kept as a link
- Maths g5-g6: 1 final anchors out of 2 usable candidates -> chain broken

## Linked chains

- Arabic arabic_chain1 (grades 1): N=179, items=52, anchor items used=0, model=1PL, fit=2PL_failed: 2PL_bad_discrimination | 1PL: ok
- Arabic arabic_chain2 (grades 2,3,4,5,6): N=990, items=149, anchor items used=14, model=1PL, fit=2PL_failed: 2PL_bad_discrimination | 1PL: ok
- French french_chain1 (grades 1,2,3,4,5,6): N=1184, items=193, anchor items used=29, model=1PL, fit=2PL_failed: not_converged | 1PL: ok
- Maths maths_chain1 (grades 1): N=180, items=26, anchor items used=0, model=2PL, fit=ok
- Maths maths_chain2 (grades 2,3,4,5): N=789, items=107, anchor items used=10, model=1PL, fit=2PL_failed: not_converged | 1PL: ok
- Maths maths_chain3 (grades 6): N=185, items=26, anchor items used=0, model=1PL, fit=2PL_failed: not_converged | 1PL: ok

## Grade means on linked scales

- Arabic arabic_chain1 grade 1: theta mean=0.041, treated=0.603, control=-0.594, treated-control gap=1.197
- Arabic arabic_chain2 grade 2: theta mean=0.201, treated=0.269, control=0.133, treated-control gap=0.136
- Arabic arabic_chain2 grade 3: theta mean=0.058, treated=0.135, control=-0.019, treated-control gap=0.154
- Arabic arabic_chain2 grade 4: theta mean=-0.248, treated=-0.144, control=-0.351, treated-control gap=0.207
- Arabic arabic_chain2 grade 5: theta mean=-0.030, treated=0.103, control=-0.157, treated-control gap=0.259
- Arabic arabic_chain2 grade 6: theta mean=0.019, treated=0.070, control=-0.029, treated-control gap=0.099
- French french_chain1 grade 1: theta mean=0.360, treated=0.604, control=0.104, treated-control gap=0.500
- French french_chain1 grade 2: theta mean=0.049, treated=0.291, control=-0.195, treated-control gap=0.486
- French french_chain1 grade 3: theta mean=0.349, treated=0.533, control=0.165, treated-control gap=0.368
- French french_chain1 grade 4: theta mean=-0.372, treated=-0.166, control=-0.578, treated-control gap=0.413
- French french_chain1 grade 5: theta mean=-0.320, treated=-0.123, control=-0.507, treated-control gap=0.384
- French french_chain1 grade 6: theta mean=-0.064, treated=0.104, control=-0.224, treated-control gap=0.328
- Maths maths_chain1 grade 1: theta mean=-0.000, treated=0.243, control=-0.272, treated-control gap=0.515
- Maths maths_chain2 grade 2: theta mean=0.065, treated=0.166, control=-0.035, treated-control gap=0.201
- Maths maths_chain2 grade 3: theta mean=0.103, treated=0.145, control=0.062, treated-control gap=0.082
- Maths maths_chain2 grade 4: theta mean=-0.047, treated=0.090, control=-0.183, treated-control gap=0.272
- Maths maths_chain2 grade 5: theta mean=-0.127, treated=0.122, control=-0.352, treated-control gap=0.475
- Maths maths_chain3 grade 6: theta mean=0.000, treated=0.425, control=-0.402, treated-control gap=0.828
