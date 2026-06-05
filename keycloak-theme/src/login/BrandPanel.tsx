import type { ReactNode } from "react";

// The branded right-hand panel shared by the Login and Register pages:
// aura overlay, eyebrow, headline, a static code sample, and the stats row.
// Kept identical across both so the two-panel auth screens stay consistent.
export function BrandPanel() {
    return (
        <div className="lp-pane-right">
            <div
                style={{
                    position: "absolute",
                    inset: 0,
                    background:
                        "radial-gradient(700px 500px at 80% 20%, rgba(232, 132, 63, 0.10), transparent 60%)," +
                        "radial-gradient(900px 600px at -10% 110%, rgba(1, 70, 148, 0.4), transparent 60%)",
                    pointerEvents: "none"
                }}
            />
            <div style={{ position: "relative", zIndex: 1, display: "flex", flexDirection: "column", height: "100%", gap: 28 }}>
                <span className="eyebrow">/ live · api gateway</span>
                <h2 style={{ fontSize: 40, fontWeight: 400, lineHeight: 1.1, letterSpacing: "-0.025em", margin: 0, color: "var(--ink-100)", maxWidth: 480 }}>
                    Every API behind one{" "}
                    <span style={{ fontStyle: "italic", fontFamily: "'IBM Plex Serif', serif", color: "var(--orange-500)" }}>
                        gateway
                    </span>
                    .
                </h2>

                <CodeSample />

                <div
                    style={{
                        marginTop: "auto",
                        display: "grid",
                        gridTemplateColumns: "repeat(3, 1fr)",
                        gap: 0,
                        borderTop: "1px solid var(--navy-line)",
                        paddingTop: 24
                    }}
                >
                    <Stat num="147" unit="" label="Services onboarded" accent />
                    <Stat num="1.4B" unit="/d" label="Requests proxied" />
                    <Stat num="4" unit="min" label="Spec → live" />
                </div>
            </div>
        </div>
    );
}

function Stat(props: { num: string; unit: string; label: string; accent?: boolean }) {
    const { num, unit, label, accent } = props;
    return (
        <div style={{ display: "flex", flexDirection: "column", gap: 6, paddingRight: 18 }}>
            <span style={{ fontFamily: "var(--font-portal-mono)", fontSize: 22, fontWeight: 500, letterSpacing: "-0.02em", color: "var(--ink-100)" }}>
                {num}
                {unit && <span style={{ fontSize: 14, color: accent ? "var(--orange-500)" : "var(--ink-400)" }}> {unit}</span>}
            </span>
            <span style={{ fontFamily: "var(--font-portal-mono)", fontSize: 10, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--ink-400)" }}>
                {label}
            </span>
        </div>
    );
}

// Static code sample (no live timer — keeps the theme bundle lean).
function CodeSample() {
    return (
        <div className="code-panel">
            <div className="code-panel-head">
                <div className="code-panel-tabs">
                    <span className="tab active">javascript</span>
                    <span className="tab">python</span>
                    <span className="tab">curl</span>
                </div>
                <div className="code-panel-meta">GET /v1/orders/8f2a</div>
            </div>
            <div className="code-panel-body">
                <Line n={1}><span className="tok-com">{"// Any onboarded API, one gateway, one token"}</span></Line>
                <Line n={2}><span className="tok-key">const</span>{" res = "}<span className="tok-key">await</span><span className="tok-fn"> fetch</span>{"("}</Line>
                <Line n={3}><span className="tok-str">{'  "https://api.internal/v1/orders/8f2a"'}</span>{","}</Line>
                <Line n={4}>{"  { headers: { "}<span className="tok-str">"Authorization"</span>{": "}<span className="tok-str">{"`Bearer ${token}`"}</span>{" } }"}</Line>
                <Line n={5}>{")"}</Line>
                <Line n={6}> </Line>
                <Line n={7}><span className="tok-key">const</span>{" order = "}<span className="tok-key">await</span>{" res."}<span className="tok-fn">json</span>{"()"}</Line>
                <div className="code-response">
                    <span className="method">200</span>
                    <span className="path">ok &nbsp;·&nbsp; application/json &nbsp;·&nbsp; 1.2 KB</span>
                    <span className="latency">94 ms</span>
                </div>
            </div>
        </div>
    );
}

function Line(props: { n: number; children: ReactNode }) {
    return (
        <div className="code-line">
            <span className="ln">{props.n}</span>
            <span className="src">{props.children}</span>
        </div>
    );
}
