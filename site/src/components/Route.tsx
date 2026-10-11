import { useLayoutEffect, useRef, useState } from 'react';

// The recurring Curbside route motif. Markers are placed by fraction along the path.
export const ROUTE_D = 'M24 236 C 90 236 96 150 160 140 S 250 196 300 150 S 360 52 430 64 S 520 150 576 96';

export interface RouteMarker { at: number; kind: 'braking' | 'acceleration' | 'overspeed' | 'cornering'; label: string; active?: boolean; pending?: boolean; onClick?: () => void }

const SHAPE: Record<RouteMarker['kind'], (x: number, y: number) => JSX.Element> = {
  braking: (x, y) => <rect x={x - 8} y={y - 8} width={16} height={16} rx={3} />,
  acceleration: (x, y) => <path d={`M${x} ${y - 10} L${x + 9} ${y + 7} L${x - 9} ${y + 7} Z`} />,
  overspeed: (x, y) => <circle cx={x} cy={y} r={9} />,
  cornering: (x, y) => <path d={`M${x} ${y - 10} L${x + 10} ${y} L${x} ${y + 10} L${x - 10} ${y} Z`} />,
};
export const MarkerGlyph = ({ kind }: { kind: RouteMarker['kind'] }) => (
  <svg width="18" height="18" viewBox="-12 -12 24 24" aria-hidden="true" className={`glyph ev-${kind}`}>{SHAPE[kind](0, 0)}</svg>
);

export function Route({ markers = [], progress, title, className = '' }: { markers?: RouteMarker[]; progress?: number; title: string; className?: string }) {
  const pathRef = useRef<SVGPathElement>(null);
  const [pts, setPts] = useState<{ x: number; y: number }[]>([]);
  const [car, setCar] = useState<{ x: number; y: number } | null>(null);
  const key = markers.map((m) => m.at).join();
  useLayoutEffect(() => {
    const p = pathRef.current; if (!p || !p.getTotalLength) return;
    const L = p.getTotalLength();
    setPts(markers.map((m) => p.getPointAtLength(L * m.at)));
    setCar(progress == null ? null : p.getPointAtLength(L * progress));
  }, [key, progress]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <svg className={`route ${className}`} viewBox="0 0 600 280" role="img" aria-label={title}>
      <path d={ROUTE_D} className="route-casing" />
      <path ref={pathRef} d={ROUTE_D} className="route-line" />
      <circle cx="24" cy="236" r="7" className="route-end" />
      <circle cx="576" cy="96" r="7" className="route-end" />
      {car && <circle cx={car.x} cy={car.y} r="6" className="route-car" />}
      {markers.map((m, i) => pts[i] && (
        <g key={i} className={`marker ev-${m.kind}${m.active ? ' is-active' : ''}${m.pending ? ' is-pending' : ''}`}
          onClick={m.onClick} style={m.onClick ? { cursor: 'pointer' } : undefined} aria-hidden="true">
          {SHAPE[m.kind](pts[i].x, pts[i].y)}
        </g>
      ))}
    </svg>
  );
}
