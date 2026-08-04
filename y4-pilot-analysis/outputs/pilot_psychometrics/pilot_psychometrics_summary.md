# Pilot psychometrics review

- Input file: `/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta`
- Records in raw file: 3523
- Records after deduplication: 3507
- Duplicate rows removed: 16
- Binary scored items reviewed: 430
- Non-binary item fields excluded from CTT/IRT: 6
- Primary easy/hard flag is based on the treated group (`p_treated`) so control underperformance does not drive the review.
- Missing responses are counted as incorrect for difficulty and IRT; observed-only correctness is shown alongside response rates to distinguish hard items from sparsely administered items.

## Form lay of the land

- Arabic grade 1: N=179 (treated 95, control 84), 52 binary items, avg response rate 94.4%, treated mean score 82.1%, control mean score 67.0%, alpha 0.97, IRT model 1PL
- Arabic grade 2: N=200 (treated 100, control 100), 32 binary items, avg response rate 93.9%, treated mean score 65.4%, control mean score 57.4%, alpha 0.89, IRT model 1PL
- Arabic grade 3: N=200 (treated 100, control 100), 31 binary items, avg response rate 92.1%, treated mean score 59.8%, control mean score 51.9%, alpha 0.91, IRT model 2PL
- Arabic grade 4: N=200 (treated 100, control 100), 33 binary items, avg response rate 81.7%, treated mean score 44.4%, control mean score 35.5%, alpha 0.93, IRT model 2PL
- Arabic grade 5: N=195 (treated 95, control 100), 32 binary items, avg response rate 84.2%, treated mean score 56.9%, control mean score 45.2%, alpha 0.92, IRT model 2PL
- Arabic grade 6: N=195 (treated 95, control 100), 35 binary items, avg response rate 76.1%, treated mean score 51.2%, control mean score 46.6%, alpha 0.92, IRT model 2PL
- French grade 1: N=195 (treated 100, control 95), 49 binary items, avg response rate 72.4%, treated mean score 55.6%, control mean score 38.2%, alpha 0.95, IRT model 1PL
- French grade 2: N=199 (treated 100, control 99), 50 binary items, avg response rate 74.6%, treated mean score 43.5%, control mean score 30.0%, alpha 0.95, IRT model 2PL
- French grade 3: N=200 (treated 100, control 100), 50 binary items, avg response rate 82.2%, treated mean score 52.6%, control mean score 40.9%, alpha 0.95, IRT model 1PL
- French grade 4: N=200 (treated 100, control 100), 32 binary items, avg response rate 64.1%, treated mean score 43.2%, control mean score 28.6%, alpha 0.89, IRT model 2PL
- French grade 5: N=195 (treated 95, control 100), 32 binary items, avg response rate 65.2%, treated mean score 46.2%, control mean score 31.4%, alpha 0.93, IRT model 1PL
- French grade 6: N=195 (treated 95, control 100), 32 binary items, avg response rate 72.7%, treated mean score 55.4%, control mean score 41.2%, alpha 0.92, IRT model 2PL
- Maths grade 1: N=180 (treated 95, control 85), 26 binary items, avg response rate 91.8%, treated mean score 64.8%, control mean score 52.2%, alpha 0.88, IRT model 2PL
- Maths grade 2: N=200 (treated 100, control 100), 28 binary items, avg response rate 90.9%, treated mean score 57.2%, control mean score 47.9%, alpha 0.90, IRT model 2PL
- Maths grade 3: N=199 (treated 99, control 100), 29 binary items, avg response rate 89.6%, treated mean score 54.0%, control mean score 51.6%, alpha 0.91, IRT model 2PL
- Maths grade 4: N=200 (treated 100, control 100), 29 binary items, avg response rate 94.1%, treated mean score 51.2%, control mean score 40.4%, alpha 0.89, IRT model 2PL
- Maths grade 5: N=190 (treated 90, control 100), 31 binary items, avg response rate 89.5%, treated mean score 49.6%, control mean score 31.6%, alpha 0.91, IRT model 2PL
- Maths grade 6: N=185 (treated 90, control 95), 26 binary items, avg response rate 79.3%, treated mean score 34.3%, control mean score 24.0%, alpha 0.89, IRT model 1PL

## CTT easy and hard items

### Arabic grade 1

Most easy in treated schools:
- `a122y3_nv3`: treated p=1.000, control p=0.940, response rate=100.0%, observed-only treated correctness=100.0%. Read the letters
- `a119y3_nv3`: treated p=0.989, control p=0.893, response rate=98.9%, observed-only treated correctness=98.9%. Read the letters
- `a124y3_nv3`: treated p=0.979, control p=0.869, response rate=97.8%, observed-only treated correctness=98.9%. Read the letters
Most hard in treated schools:
- `a112y3_nv3`: treated p=0.421, control p=0.321, response rate=98.9%, observed-only treated correctness=42.6%. Put the pictures in the right order. (Animals helping a cat)
- `a110y3_nv3`: treated p=0.474, control p=0.512, response rate=99.4%, observed-only treated correctness=47.4%. Listen to the story, and answer the question: Who fell in the pit ?
- `a12y3_nv3`: treated p=0.516, control p=0.500, response rate=82.1%, observed-only treated correctness=63.6%. Describe what you see in the picture: What is the boy doing ?

### Arabic grade 2

Most easy in treated schools:
- `a217`: treated p=1.000, control p=0.970, response rate=99.0%, observed-only treated correctness=100.0%. Read the letters
- `a215`: treated p=0.990, control p=0.970, response rate=100.0%, observed-only treated correctness=99.0%. Read the letters
- `a218`: treated p=0.990, control p=0.970, response rate=99.0%, observed-only treated correctness=99.0%. Read the letters
Most hard in treated schools:
- `a330y3_nv3`: treated p=0.310, control p=0.220, response rate=76.0%, observed-only treated correctness=39.7%. Use of logical connectors
- `a258_nv`: treated p=0.330, control p=0.280, response rate=98.0%, observed-only treated correctness=33.3%. Arrange the events (images) from 1 to 4 according to their sequence in the story
- `a332y3_nv3`: treated p=0.350, control p=0.310, response rate=86.5%, observed-only treated correctness=40.2%. Use of keywords

### Arabic grade 3

Most easy in treated schools:
- `a215`: treated p=1.000, control p=0.980, response rate=100.0%, observed-only treated correctness=100.0%. Read the letters
- `a218`: treated p=1.000, control p=0.940, response rate=99.5%, observed-only treated correctness=100.0%. Read the letters
- `a217`: treated p=0.990, control p=0.960, response rate=99.5%, observed-only treated correctness=99.0%. Read the letters
Most hard in treated schools:
- `a412y3_nv3`: treated p=0.250, control p=0.240, response rate=99.0%, observed-only treated correctness=25.5%. Reading comprehension text .Put (x) in front of the correct statement (What's th
- `a2102`: treated p=0.250, control p=0.240, response rate=68.0%, observed-only treated correctness=34.7%. Complete the story: writing at least 4 lines
- `a2100`: treated p=0.270, control p=0.320, response rate=76.0%, observed-only treated correctness=34.2%. Complete the story: Imagine the rest of the story based on this beginning (Do no

### Arabic grade 4

Most easy in treated schools:
- `a2108`: treated p=0.790, control p=0.640, response rate=93.0%, observed-only treated correctness=83.2%. Discussing a subject, persuading, and expressing a perspective. (Talk between a
- `a269`: treated p=0.790, control p=0.760, response rate=96.0%, observed-only treated correctness=82.3%. Producing narrative sentences based on a sequence of photos. (hunter vs. ant and
- `a413y3_nv3`: treated p=0.760, control p=0.600, response rate=98.0%, observed-only treated correctness=77.6%. Reading comprehension text .Put (x) in front of the correct statement (Why did S
Most hard in treated schools:
- `a2131`: treated p=0.180, control p=0.150, response rate=51.0%, observed-only treated correctness=34.0%. Writing an argumentative text about usage of internet : Presenting at least 3 ar
- `a526y3_nv3`: treated p=0.190, control p=0.120, response rate=66.5%, observed-only treated correctness=29.7%. What's the historical monument that's the most visited in Marrakesh ?
- `a2126`: treated p=0.220, control p=0.210, response rate=63.5%, observed-only treated correctness=35.5%. Explain how water in supplied to the gardens of Al-Manazih

### Arabic grade 5

Most easy in treated schools:
- `a2137`: treated p=0.968, control p=0.950, response rate=97.9%, observed-only treated correctness=98.9%. Take the floor and speak freely about the end of the year party: mention the act
- `a2138`: treated p=0.884, control p=0.850, response rate=93.3%, observed-only treated correctness=94.4%. Take the floor and speak freely about the end of the year party: at leat one rea
- `a2142_nv`: treated p=0.884, control p=0.810, response rate=96.4%, observed-only treated correctness=90.3%. Take the floor and speak freely about convincing a friend to not leave school :
Most hard in treated schools:
- `a2164_nv`: treated p=0.042, control p=0.030, response rate=83.1%, observed-only treated correctness=4.9%. Understanding informational texts: Put an X in front of all the similarities. 6
- `a2171`: treated p=0.295, control p=0.180, response rate=53.3%, observed-only treated correctness=49.1%. Write a text about internet use: write at least 5 lines (50 words)
- `a2163`: treated p=0.368, control p=0.250, response rate=63.1%, observed-only treated correctness=54.7%. Understanding informational texts: Extract from the text what indicates that cin

### Arabic grade 6

Most easy in treated schools:
- `a2160`: treated p=0.863, control p=0.880, response rate=99.5%, observed-only treated correctness=86.3%. Understanding informational texts: Why is theater called the father of the arts?
- `a625y3_nv3`: treated p=0.832, control p=0.830, response rate=95.4%, observed-only treated correctness=88.8%. Understanding informational texts: where does Corona appeared the first time
- `a2162_nv`: treated p=0.832, control p=0.760, response rate=93.8%, observed-only treated correctness=87.8%. Understanding informational texts: ite what each of the images attached to the t
Most hard in treated schools:
- `a629y3_nv3_el`: treated p=0.116, control p=0.140, response rate=60.5%, observed-only treated correctness=19.6%. Understanding informational texts: from the text how corona spread quickly
- `a638y3_nv3`: treated p=0.189, control p=0.130, response rate=45.6%, observed-only treated correctness=40.0%. Write a text about internet use: write at least 6 lines (60 words)
- `a630y3_nv3`: treated p=0.253, control p=0.180, response rate=43.6%, observed-only treated correctness=55.8%. Write a text about internet use: no more than 8 errors

### French grade 1

Most easy in treated schools:
- `f218`: treated p=0.990, control p=0.853, response rate=95.9%, observed-only treated correctness=100.0%. LIS LES LETTRES SUIVANTES A VOIX HAUTE:A
- `f227`: treated p=0.920, control p=0.779, response rate=91.3%, observed-only treated correctness=96.8%. LIS LES LETTRES SUIVANTES A VOIX HAUTE:O
- `f212`: treated p=0.920, control p=0.495, response rate=99.0%, observed-only treated correctness=92.0%. JE VAIS DIRE UN MOT ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: Un cahier
Most hard in treated schools:
- `f23`: treated p=0.070, control p=0.084, response rate=19.5%, observed-only treated correctness=43.8%. C'EST QUEL JOUR AUJOURD'HUI ?
- `f242`: treated p=0.140, control p=0.137, response rate=50.3%, observed-only treated correctness=25.0%. LIS LES MOTS SUIVANTS A VOIX HAUTE:fuji
- `f24`: treated p=0.250, control p=0.232, response rate=46.2%, observed-only treated correctness=52.1%. METS LE DOIGT SUR CHAQUE IMAGE ET DIS-MOI CE QUE C'EST EN FRANÇAIS :Chien

### French grade 2

Most easy in treated schools:
- `f255`: treated p=0.850, control p=0.545, response rate=97.5%, observed-only treated correctness=88.5%. JE VAIS DIRE UN MOT ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: Une fleur
- `f257`: treated p=0.810, control p=0.354, response rate=95.5%, observed-only treated correctness=88.0%. JE VAIS DIRE UNE PHRASE ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: Amine dess
- `f211`: treated p=0.800, control p=0.576, response rate=97.5%, observed-only treated correctness=83.3%. JE VAIS DIRE UN MOT ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: La fenêtre
Most hard in treated schools:
- `f23`: treated p=0.110, control p=0.232, response rate=31.7%, observed-only treated correctness=39.3%. C'EST QUEL JOUR AUJOURD'HUI ?
- `f280`: treated p=0.120, control p=0.131, response rate=69.8%, observed-only treated correctness=16.4%. LIS LES PHRASES SUIVANTES :fruits
- `f263`: treated p=0.130, control p=0.040, response rate=38.7%, observed-only treated correctness=24.1%. C'EST Lina SUR L'IMAGE. JE VAIS TE POSER DES QUESTIONS. REPONDS-MOI AVEC UNE PHR

### French grade 3

Most easy in treated schools:
- `f282`: treated p=0.860, control p=0.700, response rate=89.0%, observed-only treated correctness=88.7%. LIS LES PHRASES SUIVANTES : la
- `f281`: treated p=0.850, control p=0.690, response rate=89.0%, observed-only treated correctness=87.6%. LIS LES PHRASES SUIVANTES : à
- `f264`: treated p=0.830, control p=0.630, response rate=91.0%, observed-only treated correctness=83.8%. LIS LES MOTS SUIVANTS A VOIX HAUTE :karima
Most hard in treated schools:
- `f262`: treated p=0.100, control p=0.130, response rate=34.0%, observed-only treated correctness=24.4%. C'EST Lina SUR L'IMAGE. JE VAIS TE POSER DES QUESTIONS. REPONDS-MOI AVEC UNE PHR
- `f23`: treated p=0.110, control p=0.270, response rate=31.0%, observed-only treated correctness=36.7%. C'EST QUEL JOUR AUJOURD'HUI ?
- `f22_nv`: treated p=0.150, control p=0.100, response rate=44.5%, observed-only treated correctness=25.4%. QU'EST-CE QUE TU FAIS EN CLASSE?

### French grade 4

Most easy in treated schools:
- `f2118`: treated p=0.950, control p=0.880, response rate=98.0%, observed-only treated correctness=96.9%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f2119`: treated p=0.940, control p=0.800, response rate=98.0%, observed-only treated correctness=95.9%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
- `f247`: treated p=0.840, control p=0.580, response rate=97.5%, observed-only treated correctness=85.7%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: poule
Most hard in treated schools:
- `f2107`: treated p=0.060, control p=0.040, response rate=21.0%, observed-only treated correctness=24.0%. Lina se réveille le matin.
- `f2101`: treated p=0.060, control p=0.080, response rate=19.5%, observed-only treated correctness=27.3%. COMMENT TU VIENS A L'ECOLE ?
- `f2100`: treated p=0.090, control p=0.040, response rate=19.0%, observed-only treated correctness=37.5%. A QUELLE HEURE TU VIENS A L'ECOLE LE MATIN ?

### French grade 5

Most easy in treated schools:
- `f2118`: treated p=0.958, control p=0.880, response rate=99.0%, observed-only treated correctness=97.8%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f2119`: treated p=0.958, control p=0.810, response rate=99.5%, observed-only treated correctness=96.8%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
- `f247`: treated p=0.884, control p=0.610, response rate=99.5%, observed-only treated correctness=89.4%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: poule
Most hard in treated schools:
- `f2101`: treated p=0.116, control p=0.080, response rate=22.6%, observed-only treated correctness=40.7%. COMMENT TU VIENS A L'ECOLE ?
- `f2107`: treated p=0.137, control p=0.030, response rate=17.4%, observed-only treated correctness=59.1%. Lina se réveille le matin.
- `f2128`: treated p=0.168, control p=0.090, response rate=52.3%, observed-only treated correctness=26.2%. C'EST AMINE SUR LES IMAGES. ECRIS UNE PHRASE POUR DECRIRE L'IMAGE, COMME DANS L'

### French grade 6

Most easy in treated schools:
- `f2119`: treated p=0.989, control p=0.910, response rate=100.0%, observed-only treated correctness=98.9%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
- `f2118`: treated p=0.979, control p=0.940, response rate=100.0%, observed-only treated correctness=97.9%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f247`: treated p=0.916, control p=0.760, response rate=99.5%, observed-only treated correctness=91.6%. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: poule
Most hard in treated schools:
- `f2131`: treated p=0.105, control p=0.100, response rate=42.1%, observed-only treated correctness=21.3%. C'EST AMINE SUR LES IMAGES. ECRIS UNE PHRASE POUR DECRIRE L'IMAGE, COMME DANS L'
- `f2107`: treated p=0.147, control p=0.090, response rate=30.3%, observed-only treated correctness=40.0%. Lina se réveille le matin.
- `f2129`: treated p=0.221, control p=0.150, response rate=52.8%, observed-only treated correctness=34.4%. C'EST AMINE SUR LES IMAGES. ECRIS UNE PHRASE POUR DECRIRE L'IMAGE, COMME DANS L'

### Maths grade 1

Most easy in treated schools:
- `m21_nv`: treated p=0.968, control p=0.882, response rate=99.4%, observed-only treated correctness=96.8%. Read numbers : 6, 0, 3, 9, 2, 8, 1, 4, 7, 5
- `m221`: treated p=0.884, control p=0.682, response rate=94.4%, observed-only treated correctness=89.4%. Connect the digital clock and the analog clock with a line: (6:00)
- `m23_nv`: treated p=0.874, control p=0.800, response rate=96.7%, observed-only treated correctness=90.2%. 9+1 =
Most hard in treated schools:
- `m217_nv3`: treated p=0.084, control p=0.047, response rate=70.6%, observed-only treated correctness=12.9%. 37 − 10 =
- `m220_nv`: treated p=0.221, control p=0.141, response rate=83.9%, observed-only treated correctness=27.3%. 4 children shared equally 20 decorative beads.How many beads will each child get
- `m215_nv3`: treated p=0.221, control p=0.141, response rate=76.7%, observed-only treated correctness=28.8%. 42 + 20 =

### Maths grade 2

Most easy in treated schools:
- `m222`: treated p=0.950, control p=0.900, response rate=98.0%, observed-only treated correctness=96.0%. Connect the digital clock and the analog clock with a line: (12:00)
- `m23y3_nv3`: treated p=0.920, control p=0.680, response rate=97.0%, observed-only treated correctness=93.9%. 8+3 =
- `m221`: treated p=0.900, control p=0.890, response rate=99.0%, observed-only treated correctness=90.9%. Connect the digital clock and the analog clock with a line: (6:00)
Most hard in treated schools:
- `m239_nv2`: treated p=0.220, control p=0.550, response rate=93.0%, observed-only treated correctness=23.7%. 12 × 4
- `m240_nv3`: treated p=0.270, control p=0.560, response rate=92.0%, observed-only treated correctness=29.3%. 43 x 2
- `m252_nv`: treated p=0.320, control p=0.280, response rate=93.0%, observed-only treated correctness=33.0%. 74-46

### Maths grade 3

Most easy in treated schools:
- `m222`: treated p=0.939, control p=0.940, response rate=100.0%, observed-only treated correctness=93.9%. Connect the digital clock and the analog clock with a line: (12:00)
- `m252`: treated p=0.848, control p=0.770, response rate=98.5%, observed-only treated correctness=85.7%. 96-34 =
- `m276`: treated p=0.747, control p=0.720, response rate=92.5%, observed-only treated correctness=81.3%. Write the number of students who read White Fang
Most hard in treated schools:
- `m270`: treated p=0.222, control p=0.180, response rate=80.9%, observed-only treated correctness=25.9%. Othman left his house at nine fifteen and spent 20 minutes on his way to school.
- `m275`: treated p=0.222, control p=0.350, response rate=77.9%, observed-only treated correctness=26.5%. The students of the third level at the school created a garden in the shape of a
- `m268_nv3`: treated p=0.283, control p=0.340, response rate=78.9%, observed-only treated correctness=32.2%. The grand-mother bought 5 chickens, each chicken costs 31 dirhams. Calculate in

### Maths grade 4

Most easy in treated schools:
- `m230`: treated p=0.900, control p=0.760, response rate=99.0%, observed-only treated correctness=90.9%. 5 x 6 =
- `m2103_nv3`: treated p=0.820, control p=0.600, response rate=96.5%, observed-only treated correctness=83.7%. I have four equal sides and four right angles. who am I ?
- `m283_nv`: treated p=0.770, control p=0.620, response rate=92.5%, observed-only treated correctness=83.7%. 8 x 11 =
Most hard in treated schools:
- `m295_nv3`: treated p=0.050, control p=0.100, response rate=92.0%, observed-only treated correctness=5.4%. Hamid works five days a week. Each day he works, he earns 65 dirhams. ✓ Calculat
- `m298_nv3`: treated p=0.230, control p=0.160, response rate=93.5%, observed-only treated correctness=24.5%. What is the decimal representation equivalent to the fraction: 6/10. Choices: 1,
- `m260`: treated p=0.270, control p=0.180, response rate=92.0%, observed-only treated correctness=28.4%. determine the value represented by the number written in bold in each number: 5

### Maths grade 5

Most easy in treated schools:
- `m282_nv`: treated p=0.911, control p=0.770, response rate=98.9%, observed-only treated correctness=91.1%. 4x9 =
- `m2131_nv`: treated p=0.822, control p=0.590, response rate=88.4%, observed-only treated correctness=87.1%. (9 – 3) × 5 =
- `m2138`: treated p=0.822, control p=0.680, response rate=93.2%, observed-only treated correctness=85.1%. Complete  a drawing of the column for the number of bicycles of type No. 4.
Most hard in treated schools:
- `m2119_nv3`: treated p=0.044, control p=0.070, response rate=95.3%, observed-only treated correctness=4.7%. 5/3  + 3/2 =
- `m2120_nv3`: treated p=0.056, control p=0.050, response rate=94.2%, observed-only treated correctness=6.0%. 9/5 - 1/2 =
- `m2121_nv`: treated p=0.056, control p=0.010, response rate=93.2%, observed-only treated correctness=6.0%. 2/5 + 1/10 =

### Maths grade 6

Most easy in treated schools:
- `m2140_nv`: treated p=0.733, control p=0.389, response rate=88.6%, observed-only treated correctness=79.5%. 624/4=
- `m61y3_nv3`: treated p=0.700, control p=0.600, response rate=92.4%, observed-only treated correctness=75.0%. 800x7=
- `m2107`: treated p=0.689, control p=0.505, response rate=81.1%, observed-only treated correctness=78.5%. 72/6=
Most hard in treated schools:
- `m610y3_nv3`: treated p=0.056, control p=0.032, response rate=84.3%, observed-only treated correctness=6.2%. Put in ascending order: 12,315; 12+3/100; 12; 121/10, 12,3
- `m623y3_nv3`: treated p=0.056, control p=0.021, response rate=62.7%, observed-only treated correctness=7.8%. Samira spends 1/4 of her time reading and 1/8 drawing. How much time does she sp
- `m620y3_nv3`: treated p=0.067, control p=0.211, response rate=78.4%, observed-only treated correctness=8.6%. Conclude the size of the angle ACB

## IRT extreme items

### Arabic grade 1 (1PL)
- Fit note: 2PL_failed: 2PL_bad_discrimination | 1PL: ok
Most easy by IRT difficulty:
- `a122y3_nv3`: b=-5.46, a=1.00, treated p=1.000. Read the letters
- `a117y3_nv3`: b=-4.63, a=1.00, treated p=0.979. Read the letters
- `a115y3_nv3`: b=-4.47, a=1.00, treated p=0.979. Read the letters
Most hard by IRT difficulty:
- `a112y3_nv3`: b=0.98, a=1.00, treated p=0.421. Put the pictures in the right order. (Animals helping a cat)
- `a248y3_nv3`: b=0.67, a=1.00, treated p=0.547. write with the diacritical marks (vowel signs): Salim
- `a110y3_nv3`: b=0.25, a=1.00, treated p=0.474. Listen to the story, and answer the question: Who fell in the pit ?

### Arabic grade 2 (1PL)
- Fit note: 2PL_failed: not_converged | 1PL: ok
Most easy by IRT difficulty:
- `a217`: b=-5.01, a=1.00, treated p=1.000. Read the letters
- `a215`: b=-4.70, a=1.00, treated p=0.990. Read the letters
- `a218`: b=-4.70, a=1.00, treated p=0.990. Read the letters
Most hard by IRT difficulty:
- `a330y3_nv3`: b=1.36, a=1.00, treated p=0.310. Use of logical connectors
- `a258_nv`: b=1.10, a=1.00, treated p=0.330. Arrange the events (images) from 1 to 4 according to their sequence in the story
- `a332y3_nv3`: b=0.95, a=1.00, treated p=0.350. Use of keywords

### Arabic grade 3 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `a217`: b=-4.57, a=0.88, treated p=0.990. Read the letters
- `a214_nv`: b=-3.10, a=1.54, treated p=0.980. Read the letters
- `a215`: b=-2.66, a=4.05, treated p=1.000. Read the letters
Most hard by IRT difficulty:
- `a412y3_nv3`: b=2.70, a=0.43, treated p=0.250. Reading comprehension text .Put (x) in front of the correct statement (What's th
- `a422y3_nv3`: b=1.26, a=1.55, treated p=0.290. Composing simple sentences based on untidy words: (The kids always practice spor
- `a291`: b=0.99, a=0.98, treated p=0.350. Reading comprehension text Mark (X) in front of the general idea of the text (th

### Arabic grade 4 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `a413y3_nv3`: b=-1.30, a=0.63, treated p=0.760. Reading comprehension text .Put (x) in front of the correct statement (Why did S
- `a269`: b=-0.96, a=2.19, treated p=0.790. Producing narrative sentences based on a sequence of photos. (hunter vs. ant and
- `a2108`: b=-0.63, a=3.57, treated p=0.790. Discussing a subject, persuading, and expressing a perspective. (Talk between a
Most hard by IRT difficulty:
- `a526y3_nv3`: b=2.02, a=0.99, treated p=0.190. What's the historical monument that's the most visited in Marrakesh ?
- `a516y3_nv3`: b=1.87, a=0.62, treated p=0.310. Reading comprehension: What's the proof that Nouhaila and Badr's father is proud
- `a422y3_nv3`: b=1.46, a=1.54, treated p=0.240. Composing simple sentences based on untidy words: (The kids always practice spor

### Arabic grade 5 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `a2137`: b=-2.10, a=3.08, treated p=0.968. Take the floor and speak freely about the end of the year party: mention the act
- `a2138`: b=-1.79, a=1.38, treated p=0.884. Take the floor and speak freely about the end of the year party: at leat one rea
- `a2142_nv`: b=-1.43, a=1.77, treated p=0.884. Take the floor and speak freely about convincing a friend to not leave school :
Most hard by IRT difficulty:
- `a2164_nv`: b=3.86, a=0.95, treated p=0.042. Understanding informational texts: Put an X in front of all the similarities. 6
- `a2171`: b=0.92, a=2.18, treated p=0.295. Write a text about internet use: write at least 5 lines (50 words)
- `a2159`: b=0.71, a=0.94, treated p=0.421. What are the arts the text talks about?

### Arabic grade 6 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `a2160`: b=-3.83, a=0.53, treated p=0.863. Understanding informational texts: Why is theater called the father of the arts?
- `a2162_nv`: b=-1.92, a=0.79, treated p=0.832. Understanding informational texts: ite what each of the images attached to the t
- `a625y3_nv3`: b=-1.74, a=1.12, treated p=0.832. Understanding informational texts: where does Corona appeared the first time
Most hard by IRT difficulty:
- `a629y3_nv3_el`: b=1.77, a=1.43, treated p=0.116. Understanding informational texts: from the text how corona spread quickly
- `a638y3_nv3`: b=1.10, a=3.32, treated p=0.189. Write a text about internet use: write at least 6 lines (60 words)
- `a630y3_nv3`: b=0.84, a=4.41, treated p=0.253. Write a text about internet use: no more than 8 errors

### French grade 1 (1PL)
- Fit note: 2PL_failed: not_converged | 1PL: ok
Most easy by IRT difficulty:
- `f218`: b=-3.32, a=1.00, treated p=0.990. LIS LES LETTRES SUIVANTES A VOIX HAUTE:A
- `f227`: b=-2.43, a=1.00, treated p=0.920. LIS LES LETTRES SUIVANTES A VOIX HAUTE:O
- `f249`: b=-1.77, a=1.00, treated p=0.780. COPIE CHAQUE MOT UNE SEULE FOIS: Je parle
Most hard by IRT difficulty:
- `f23`: b=3.42, a=1.00, treated p=0.070. C'EST QUEL JOUR AUJOURD'HUI ?
- `f242`: b=2.56, a=1.00, treated p=0.140. LIS LES MOTS SUIVANTS A VOIX HAUTE:fuji
- `f22`: b=2.04, a=1.00, treated p=0.310. TU ES EN QUELLE CLASSE ?

### French grade 2 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `f211`: b=-0.99, a=0.93, treated p=0.800. JE VAIS DIRE UN MOT ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: La fenêtre
- `f255`: b=-0.97, a=1.05, treated p=0.850. JE VAIS DIRE UN MOT ET TU DOIS ME MONTRER L'IMAGE CORRESPONDANTE: Une fleur
- `f245`: b=-0.62, a=1.18, treated p=0.730. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: vache
Most hard by IRT difficulty:
- `f293`: b=3.40, a=0.19, treated p=0.340. LIS LA QUESTION ET MONTRE-MOI LA BONNE REPONSE. QUE FAIT ALI ? Ali saute sur le
- `f22_nv`: b=2.46, a=0.81, treated p=0.240. QU'EST-CE QUE TU FAIS EN CLASSE?
- `f23`: b=2.32, a=0.75, treated p=0.110. C'EST QUEL JOUR AUJOURD'HUI ?

### French grade 3 (1PL)
- Fit note: 2PL_failed: 2PL_bad_discrimination | 1PL: ok
Most easy by IRT difficulty:
- `f282`: b=-1.85, a=1.00, treated p=0.860. LIS LES PHRASES SUIVANTES : la
- `f281`: b=-1.77, a=1.00, treated p=0.850. LIS LES PHRASES SUIVANTES : à
- `f246`: b=-1.66, a=1.00, treated p=0.810. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE:tapis
Most hard by IRT difficulty:
- `f262`: b=2.87, a=1.00, treated p=0.100. C'EST Lina SUR L'IMAGE. JE VAIS TE POSER DES QUESTIONS. REPONDS-MOI AVEC UNE PHR
- `f22_nv`: b=2.75, a=1.00, treated p=0.150. QU'EST-CE QUE TU FAIS EN CLASSE?
- `f263`: b=2.32, a=1.00, treated p=0.230. C'EST Lina SUR L'IMAGE. JE VAIS TE POSER DES QUESTIONS. REPONDS-MOI AVEC UNE PHR

### French grade 4 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `f2118`: b=-1.54, a=3.34, treated p=0.950. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f298`: b=-1.29, a=0.97, treated p=0.770. ECRIS UNE PHRASE A PARTIR DES MOTS SUIVANTS: rouge, est, mon cartable
- `f2119`: b=-1.25, a=3.58, treated p=0.940. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
Most hard by IRT difficulty:
- `f2101`: b=3.33, a=0.87, treated p=0.060. COMMENT TU VIENS A L'ECOLE ?
- `f2107`: b=2.53, a=1.55, treated p=0.060. Lina se réveille le matin.
- `f2100`: b=2.05, a=1.98, treated p=0.090. A QUELLE HEURE TU VIENS A L'ECOLE LE MATIN ?

### French grade 5 (1PL)
- Fit note: 2PL_failed: 2PL_bad_discrimination | 1PL: ok
Most easy by IRT difficulty:
- `f2118`: b=-3.49, a=1.00, treated p=0.958. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f2119`: b=-2.96, a=1.00, treated p=0.958. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
- `f247`: b=-1.64, a=1.00, treated p=0.884. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: poule
Most hard by IRT difficulty:
- `f2107`: b=3.59, a=1.00, treated p=0.137. Lina se réveille le matin.
- `f2101`: b=3.32, a=1.00, treated p=0.116. COMMENT TU VIENS A L'ECOLE ?
- `f2100`: b=3.09, a=1.00, treated p=0.168. A QUELLE HEURE TU VIENS A L'ECOLE LE MATIN ?

### French grade 6 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `f2119`: b=-2.39, a=1.66, treated p=0.989. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: école
- `f2118`: b=-2.26, a=2.11, treated p=0.979. RELIE CHAQUE MOT A L'IMAGE CORRESPONDANTE: tomate
- `f298`: b=-1.51, a=1.74, treated p=0.884. ECRIS UNE PHRASE A PARTIR DES MOTS SUIVANTS: rouge, est, mon cartable
Most hard by IRT difficulty:
- `f2131`: b=1.50, a=3.02, treated p=0.105. C'EST AMINE SUR LES IMAGES. ECRIS UNE PHRASE POUR DECRIRE L'IMAGE, COMME DANS L'
- `f2107`: b=1.41, a=3.04, treated p=0.147. Lina se réveille le matin.
- `f2109`: b=1.22, a=1.87, treated p=0.326. Lina nage dans la mer.

### Maths grade 1 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `m222`: b=-2.00, a=1.03, treated p=0.863. Connect the digital clock and the analog clock with a line: (12:00)
- `m21_nv`: b=-1.66, a=3.45, treated p=0.968. Read numbers : 6, 0, 3, 9, 2, 8, 1, 4, 7, 5
- `m225`: b=-1.59, a=1.01, treated p=0.842. Draw with a ruler the required geometric shape: rectangle
Most hard by IRT difficulty:
- `m217_nv3`: b=2.13, a=1.74, treated p=0.084. 37 − 10 =
- `m220_nv`: b=1.84, a=0.95, treated p=0.221. 4 children shared equally 20 decorative beads.How many beads will each child get
- `m215_nv3`: b=1.54, a=1.23, treated p=0.221. 42 + 20 =

### Maths grade 2 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `m222`: b=-2.90, a=1.01, treated p=0.950. Connect the digital clock and the analog clock with a line: (12:00)
- `m221`: b=-2.25, a=1.18, treated p=0.900. Connect the digital clock and the analog clock with a line: (6:00)
- `m23y3_nv3`: b=-1.51, a=1.13, treated p=0.920. 8+3 =
Most hard by IRT difficulty:
- `m230_nv`: b=0.89, a=1.49, treated p=0.320. 4 x 8 =
- `m243_nv3`: b=0.86, a=1.58, treated p=0.360. Amina distributed 12 pencils equally among 4 students. How many pencils will eac
- `m242_nv3`: b=0.86, a=1.68, treated p=0.380. Laila has 15 cookies. She wants to put 3 cookies on each plate. How many plates

### Maths grade 3 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `m222`: b=-3.26, a=0.96, treated p=0.939. Connect the digital clock and the analog clock with a line: (12:00)
- `m252`: b=-1.29, a=1.53, treated p=0.848. 96-34 =
- `m280_nv3`: b=-1.03, a=1.54, treated p=0.737. Which child spent the most time in the race?
Most hard by IRT difficulty:
- `m270`: b=1.18, a=1.68, treated p=0.222. Othman left his house at nine fifteen and spent 20 minutes on his way to school.
- `m275`: b=0.72, a=1.99, treated p=0.222. The students of the third level at the school created a garden in the shape of a
- `m259`: b=0.66, a=2.85, treated p=0.293. Write the appropriate number in digits next to each of the following statements:

### Maths grade 4 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `m230`: b=-1.09, a=3.57, treated p=0.900. 5 x 6 =
- `m2103_nv3`: b=-0.87, a=1.35, treated p=0.820. I have four equal sides and four right angles. who am I ?
- `m230_nv`: b=-0.81, a=1.39, treated p=0.740. 4 x 8 =
Most hard by IRT difficulty:
- `m2104_nv`: b=2.74, a=0.25, treated p=0.400. How do you call Lines that are always the same distance apart and never cross? a
- `m298_nv3`: b=2.72, a=0.55, treated p=0.230. What is the decimal representation equivalent to the fraction: 6/10. Choices: 1,
- `m295_nv3`: b=2.36, a=1.33, treated p=0.050. Hamid works five days a week. Each day he works, he earns 65 dirhams. ✓ Calculat

### Maths grade 5 (2PL)
- Fit note: ok
Most easy by IRT difficulty:
- `m282_nv`: b=-1.35, a=1.86, treated p=0.911. 4x9 =
- `m2138`: b=-1.10, a=1.27, treated p=0.822. Complete  a drawing of the column for the number of bicycles of type No. 4.
- `m2101`: b=-1.00, a=0.79, treated p=0.722. Enclose with a line the value that is equal to  5.3 km 20 m in meters. Choices:
Most hard by IRT difficulty:
- `m2104_nv`: b=3.07, a=0.32, treated p=0.278. How do you call Lines that are always the same distance apart and never cross? a
- `m2123_nv`: b=3.04, a=0.25, treated p=0.378. Omar bought 10 pens at a price of 7.5 dirhams each. He gave the shop assistant a
- `m2121_nv`: b=2.84, a=1.52, treated p=0.056. 2/5 + 1/10 =

### Maths grade 6 (1PL)
- Fit note: 2PL_failed: not_converged | 1PL: ok
Most easy by IRT difficulty:
- `m62y3_nv3`: b=-1.05, a=1.00, treated p=0.689. 50x60=
- `m61y3_nv3`: b=-0.91, a=1.00, treated p=0.700. 800x7=
- `m618y3_nv3`: b=-0.60, a=1.00, treated p=0.689. In a summer camp, 1 chaperone was assigned for each 15 kids Fill the table: 1/X;
Most hard by IRT difficulty:
- `m623y3_nv3`: b=4.38, a=1.00, treated p=0.056. Samira spends 1/4 of her time reading and 1/8 drawing. How much time does she sp
- `m610y3_nv3`: b=4.22, a=1.00, treated p=0.056. Put in ascending order: 12,315; 12+3/100; 12; 121/10, 12,3
- `m617y3_nv3`: b=3.23, a=1.00, treated p=0.089. c) Calculate the area of the colored part of the figure in cm²

## Anchor review

- Arabic g1-g2: 3 shared items, 0 usable anchors, 0 low-coverage anchors, 3 extreme anchors, 0 weak-discrimination anchors.
- Arabic g2-g3: 9 shared items, 2 usable anchors, 0 low-coverage anchors, 7 extreme anchors, 0 weak-discrimination anchors.
- Arabic g3-g4: 7 shared items, 7 usable anchors, 0 low-coverage anchors, 0 extreme anchors, 0 weak-discrimination anchors.
- Arabic g4-g5: 4 shared items, 3 usable anchors, 1 low-coverage anchors, 0 extreme anchors, 0 weak-discrimination anchors.
- Arabic g5-g6: 14 shared items, 6 usable anchors, 4 low-coverage anchors, 4 extreme anchors, 0 weak-discrimination anchors.
- French g1-g2: 9 shared items, 3 usable anchors, 5 low-coverage anchors, 1 extreme anchors, 0 weak-discrimination anchors.
- French g2-g3: 50 shared items, 23 usable anchors, 18 low-coverage anchors, 8 extreme anchors, 1 weak-discrimination anchors.
- French g3-g4: 11 shared items, 8 usable anchors, 2 low-coverage anchors, 1 extreme anchors, 0 weak-discrimination anchors.
- French g4-g5: 32 shared items, 11 usable anchors, 17 low-coverage anchors, 4 extreme anchors, 0 weak-discrimination anchors.
- French g5-g6: 32 shared items, 9 usable anchors, 17 low-coverage anchors, 6 extreme anchors, 0 weak-discrimination anchors.
- Maths g1-g2: 5 shared items, 1 usable anchors, 0 low-coverage anchors, 4 extreme anchors, 0 weak-discrimination anchors.
- Maths g2-g3: 6 shared items, 3 usable anchors, 2 low-coverage anchors, 1 extreme anchors, 0 weak-discrimination anchors.
- Maths g3-g4: 6 shared items, 5 usable anchors, 0 low-coverage anchors, 1 extreme anchors, 0 weak-discrimination anchors.
- Maths g4-g5: 6 shared items, 4 usable anchors, 0 low-coverage anchors, 1 extreme anchors, 1 weak-discrimination anchors.
- Maths g5-g6: 4 shared items, 2 usable anchors, 2 low-coverage anchors, 0 extreme anchors, 0 weak-discrimination anchors.
