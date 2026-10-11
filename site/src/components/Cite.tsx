import { ref } from '../data/references';
/** Inline citation chip linking to the bibliography entry and the source. */
export function Cite({ id }: { id: string }) {
  const r = ref(id);
  return <a className="cite" href={r.url} target="_blank" rel="noreferrer" title={`${r.authors} — ${r.title}`} aria-label={`Source ${id}: ${r.authors}, ${r.title} (opens in new tab)`}>{id}</a>;
}
