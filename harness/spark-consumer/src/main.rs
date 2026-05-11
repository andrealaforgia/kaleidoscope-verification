//! spark-consumer — EDD test fixture for kaleidoscope's Spark SDK.
//!
//! Each `--scenario` corresponds to one or more S-prefix expectations
//! in the catalogue. The binary prints a single structured outcome
//! line on stdout that the catalogue runner asserts against. Real
//! OTLP traffic (for round-trip expectations) goes out the Spark
//! exporter, which the harness has configured to point at the
//! aperture container in the same docker compose network.

use clap::Parser;
use std::process::ExitCode;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(
    name = "spark-consumer",
    about = "EDD test fixture: exercises spark::init scenarios and emits structured outcome lines."
)]
struct Args {
    /// Scenario name. See the match below for the canonical list.
    #[arg(long)]
    scenario: String,

    /// service.name to pass to SparkConfig::for_service. Empty
    /// string deliberately triggers the missing-required-attribute
    /// path for `s06-missing-service-name`.
    #[arg(long, default_value = "spark-consumer-default")]
    service_name: String,

    /// Optional endpoint override (SparkConfig::with_endpoint).
    #[arg(long)]
    endpoint: Option<String>,

    /// When set, the scenario calls require_tenant_id().
    #[arg(long, default_value_t = false)]
    require_tenant_id: bool,

    /// Optional tenant.id (SparkConfig::with_tenant_id).
    #[arg(long)]
    tenant_id: Option<String>,
}

fn build_config(args: &Args) -> spark::SparkConfig {
    let mut cfg = spark::SparkConfig::for_service(args.service_name.clone());
    if args.require_tenant_id {
        cfg = cfg.require_tenant_id();
    }
    if let Some(t) = &args.tenant_id {
        cfg = cfg.with_tenant_id(t.clone());
    }
    if let Some(e) = &args.endpoint {
        cfg = cfg.with_endpoint(e.clone());
    }
    // Tight flush timeout so the consumer doesn't hang in shutdown
    // when expected-broken scenarios kill the downstream.
    cfg = cfg.with_flush_timeout(Duration::from_millis(2000));
    cfg
}

fn report(scenario: &str, result: &str, detail: &str) {
    // One structured outcome line that per-expectation runners grep.
    println!("scenario={scenario} result={result} detail={detail}");
}

fn classify_err(e: &spark::SparkError) -> (&'static str, String) {
    match e {
        spark::SparkError::MissingRequiredAttribute { name } => {
            ("MissingRequiredAttribute", format!("name={name}"))
        }
        spark::SparkError::InvalidEndpoint { endpoint, reason } => (
            "InvalidEndpoint",
            format!("endpoint={endpoint} reason={reason}"),
        ),
        spark::SparkError::GlobalAlreadyInitialised => {
            ("GlobalAlreadyInitialised", String::new())
        }
        spark::SparkError::ExporterInitFailed { reason, .. } => {
            ("ExporterInitFailed", format!("reason={reason}"))
        }
        _ => ("UnknownVariant", format!("{e}")),
    }
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> ExitCode {
    let args = Args::parse();
    let scenario = args.scenario.clone();
    eprintln!("[spark-consumer] starting scenario={scenario}");

    match scenario.as_str() {
        // S06 — MissingRequiredAttribute { name: "service.name" }
        // when the SparkConfig is built with an empty service name.
        "s06-missing-service-name" => {
            let cfg = spark::SparkConfig::for_service(String::new());
            match spark::init(cfg) {
                Ok(_) => {
                    report(&scenario, "fail", "init returned Ok with empty service name");
                    ExitCode::from(1)
                }
                Err(e) => {
                    let (variant, detail) = classify_err(&e);
                    if variant == "MissingRequiredAttribute" && detail == "name=service.name" {
                        report(&scenario, "ok", &format!("{variant} {detail}"));
                        ExitCode::SUCCESS
                    } else {
                        report(
                            &scenario,
                            "fail",
                            &format!("wrong error: {variant} {detail}"),
                        );
                        ExitCode::from(1)
                    }
                }
            }
        }

        // S07 — MissingRequiredAttribute { name: "tenant.id" }
        // when require_tenant_id() is set but with_tenant_id is not.
        "s07-missing-tenant-id" => {
            let cfg = spark::SparkConfig::for_service("svc".to_string()).require_tenant_id();
            match spark::init(cfg) {
                Ok(_) => {
                    report(&scenario, "fail", "init returned Ok without tenant.id");
                    ExitCode::from(1)
                }
                Err(e) => {
                    let (variant, detail) = classify_err(&e);
                    if variant == "MissingRequiredAttribute" && detail == "name=tenant.id" {
                        report(&scenario, "ok", &format!("{variant} {detail}"));
                        ExitCode::SUCCESS
                    } else {
                        report(
                            &scenario,
                            "fail",
                            &format!("wrong error: {variant} {detail}"),
                        );
                        ExitCode::from(1)
                    }
                }
            }
        }

        // S08 — InvalidEndpoint when a malformed endpoint is given.
        "s08-malformed-endpoint" => {
            let cfg = spark::SparkConfig::for_service("svc".to_string())
                .with_endpoint("not-a-valid-url");
            match spark::init(cfg) {
                Ok(_) => {
                    report(&scenario, "fail", "init returned Ok on malformed endpoint");
                    ExitCode::from(1)
                }
                Err(e) => {
                    let (variant, _detail) = classify_err(&e);
                    if variant == "InvalidEndpoint" {
                        report(&scenario, "ok", &format!("{variant} as expected"));
                        ExitCode::SUCCESS
                    } else {
                        report(&scenario, "fail", &format!("wrong error: {variant}"));
                        ExitCode::from(1)
                    }
                }
            }
        }

        // S09 — GlobalAlreadyInitialised when init is called twice
        // while the first guard is still alive.
        "s09-double-init" => {
            let cfg1 = build_config(&args);
            let _guard1 = match spark::init(cfg1) {
                Ok(g) => g,
                Err(e) => {
                    report(&scenario, "fail", &format!("first init failed: {e}"));
                    return ExitCode::from(1);
                }
            };
            let cfg2 = build_config(&args);
            let res2 = spark::init(cfg2);
            match res2 {
                Err(spark::SparkError::GlobalAlreadyInitialised) => {
                    report(&scenario, "ok", "second init returned GlobalAlreadyInitialised");
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    let (variant, _) = classify_err(&e);
                    report(&scenario, "fail", &format!("wrong error: {variant}"));
                    ExitCode::from(1)
                }
                Ok(_) => {
                    report(&scenario, "fail", "second init returned Ok");
                    ExitCode::from(1)
                }
            }
        }

        // S10 — init succeeds again after the first guard is dropped.
        "s10-reinit-after-drop" => {
            let cfg1 = build_config(&args);
            let guard1 = match spark::init(cfg1) {
                Ok(g) => g,
                Err(e) => {
                    report(&scenario, "fail", &format!("first init failed: {e}"));
                    return ExitCode::from(1);
                }
            };
            drop(guard1);
            let cfg2 = build_config(&args);
            match spark::init(cfg2) {
                Ok(_g2) => {
                    report(&scenario, "ok", "init→drop→init returned Ok the second time");
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    let (variant, _) = classify_err(&e);
                    report(
                        &scenario,
                        "fail",
                        &format!("second init failed after drop: {variant}"),
                    );
                    ExitCode::from(1)
                }
            }
        }

        // S01 — canonical init plus one span via the global tracer.
        // The span is expected to reach aperture's stderr as a
        // `event=sink_accepted signal=traces span_count>=1` line
        // with the chosen service.name on the Resource.
        "s01-init-and-emit-trace" => {
            let cfg = build_config(&args);
            let guard = match spark::init(cfg) {
                Ok(g) => g,
                Err(e) => {
                    report(&scenario, "fail", &format!("init failed: {e}"));
                    return ExitCode::from(1);
                }
            };
            // Emit one span via the global tracer that Spark installs.
            {
                use opentelemetry::trace::{Tracer, TracerProvider};
                let provider = opentelemetry::global::tracer_provider();
                let tracer = provider.tracer("spark-consumer");
                let _span = tracer.start("spark-consumer-emit-trace");
            }
            // Spark's shutdown flushes the batch before drop returns.
            drop(guard);
            report(&scenario, "ok", "init + one span + clean drop");
            ExitCode::SUCCESS
        }

        other => {
            eprintln!("unknown scenario: {other}");
            ExitCode::from(64)
        }
    }
}
