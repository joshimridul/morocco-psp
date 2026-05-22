**Anchor Recommendations**
These recommendations translate the anchor-gap audit into concrete item suggestions for the boundaries where the vertical scale is currently broken or too thin. I focused on the edges that are actually missing or fragile in the current linking results:

- `Arabic g1-g2`: broken (`0` final anchors)
- `Arabic g2-g3`: weak (`2` final anchors)
- `Arabic g5-g6`: fragile (`2` final anchors)
- `Maths g1-g2`: broken (`1` final anchor)
- `Maths g5-g6`: broken (`1` final anchor)

I did not add new French recommendations here because the French chain already links throughout Grades 1-6, even if the `g1-g2` edge is still thinner than ideal.

**Priority Order**
- `Critical`: add anchors first at `Arabic g1-g2`, `Maths g1-g2`, and `Maths g5-g6`
- `Strengthen`: then expand `Arabic g2-g3` and `Arabic g5-g6`

**Arabic**
| Boundary | Action | Item | Direction | Why |
| --- | --- | --- | --- | --- |
| `g1-g2` | Add | `a245y3_nv3` | `Grade 1 -> Grade 2` | Strong discrimination, good completion, and hard enough in Grade 1 to avoid the immediate ceiling problem that broke the current edge. |
| `g1-g2` | Add | `a247y3_nv3` | `Grade 1 -> Grade 2` | Structured diacritics-writing item with good spread and high completion. |
| `g1-g2` | Add | `a249y3_nv3` | `Grade 1 -> Grade 2` | Another well-functioning Grade 1 writing item in the same skill family. |
| `g1-g2` | Add | `a251y3_nv3` | `Grade 1 -> Grade 2` | Productive oral/comprehension item that should give the edge more range than the current shared prompt set. |
| `g2-g3` | Keep | `a261_nv` | already shared | One of only two current anchors that already works across Grades 2-3. |
| `g2-g3` | Keep | `a324y3_nv3` | already shared | Current shared anchor that already survives the edge. |
| `g2-g3` | Add | `a251` | `Grade 2 -> Grade 3` | Selected-response comprehension item with strong completion and non-extreme difficulty. |
| `g2-g3` | Add | `a263_nv3` | `Grade 2 -> Grade 3` | Excellent discrimination and mid-range difficulty. |
| `g2-g3` | Add | `a322y3_nv3` | `Grade 2 -> Grade 3` | Very high completion and good discrimination; useful as a more structured writing anchor. |
| `g5-g6` | Keep | `a2145_nv` | already shared | One of the few anchors that currently links Grades 5-6. |
| `g5-g6` | Keep | `a2161` | already shared | Current shared anchor that survives the edge. |
| `g5-g6` | Add | `a2159` | `Grade 5 -> Grade 6` | Moderately difficult comprehension item with good completion; adds needed range. |
| `g5-g6` | Add | `a2152` | `Grade 5 -> Grade 6` | Well-functioning text-based comprehension item that should travel better than the more unstable shared tasks. |
| `g5-g6` | Add | `a2153` | `Grade 5 -> Grade 6` | Structured comprehension item with solid discrimination and completion. |
| `g5-g6` | Add | `a2155` | `Grade 5 -> Grade 6` | Useful mid-difficulty justification item if the rubric is tightly aligned in both grades. |

**Maths**
| Boundary | Action | Item | Direction | Why |
| --- | --- | --- | --- | --- |
| `g1-g2` | Keep | `m210` | already shared | The only current Maths Grades 1-2 anchor that works. |
| `g1-g2` | Add | `m216_nv3` | `Grade 1 -> Grade 2` | Harder arithmetic item that should still have room in Grade 2. |
| `g1-g2` | Add | `m218_nv` | `Grade 1 -> Grade 2` | Reasoning item with moderate difficulty and high completion. |
| `g1-g2` | Add | `m219_nv3` | `Grade 1 -> Grade 2` | One of the strongest Grade 1 reasoning items for this edge. |
| `g1-g2` | Add | `m213_nv` | `Grade 1 -> Grade 2` | High-completion ordering item with strong discrimination; more stable than the current very easy shared numeracy items. |
| `g5-g6` | Keep | `m2139_nv` | already shared | The only current Maths Grades 5-6 anchor that clearly works. |
| `g5-g6` | Add | `m2125_nv3` | `Grade 5 -> Grade 6` | Strong mid-difficulty quantitative reasoning item that should expand the edge without overshooting. |
| `g5-g6` | Add | `m2126_nv3` | `Grade 5 -> Grade 6` | Very good discrimination and completion; one of the cleanest new candidates. |
| `g5-g6` | Add | `m2133_nv3` | `Grade 5 -> Grade 6` | Geometry/measurement anchor with acceptable difficulty and strong completion. |
| `g5-g6` | Add | `m2135` | `Grade 5 -> Grade 6` | Appropriately challenging geometry item that gives this link more range than the current one-anchor setup. |

**Use**
The full row-level file is [anchor_recommendations.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/anchor_recommendations.csv). If the team is short on time, I would start by implementing the `Critical` edges first, because those are the boundaries that currently break the linked scale.
