# Address Verification

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Verify and standardize addresses in bulk against authoritative postal data using the Amazon Location Service **Jobs API** (`StartJob` with Action `ValidateAddress`).

**Distinction from Address Input**: The address-input reference covers the interactive UI/UX of collecting a single address from a user (autocomplete, type-ahead, and resolving a typed address to coordinates with Geocode). This reference covers **postal address validation** — verifying and standardizing addresses against authoritative reference data, producing a match-confidence verdict and per-component status.

**Address validation is NOT geocoding.** Geocode (`geo-places:Geocode`) resolves an address to coordinates and returns a best-match label; it does NOT return a validation verdict. To verify and standardize addresses you MUST use the asynchronous Jobs API — `StartJob` with Action `ValidateAddress`, then `GetJob`/`ListJobs`/`CancelJob`. Recommending Geocode (or `SearchText`) for address validation is a wrong-task answer.

## Table of Contents

- [Overview](#overview)
- [When to Validate Addresses](#when-to-validate-addresses)
- [Supported Countries](#supported-countries)
- [Job Workflow](#job-workflow)
- [Input Schema](#input-schema)
- [Starting a Validation Job](#starting-a-validation-job)
- [Tracking a Job](#tracking-a-job)
- [Interpreting Results](#interpreting-results)
- [Handling Partial Matches](#handling-partial-matches)
- [Listing and Canceling Jobs](#listing-and-canceling-jobs)
- [Error Handling](#error-handling)
- [Pricing](#pricing)
- [Best Practices](#best-practices)

## Overview

Address validation jobs process address data to verify and standardize addresses. The service:

1. **Validates** - Confirms the address exists and is deliverable by checking it against authoritative postal datasets
2. **Standardizes** - Formats the address according to official postal standards (consistent abbreviations, casing, punctuation)
3. **Corrects and completes** - Fixes spelling mistakes and appends missing components such as postal codes or street names
4. **Enriches (optional)** - Adds geographic coordinates and country-specific postal attributes when requested

Validation runs as an **asynchronous bulk job**: you stage input in Amazon S3 as Apache Parquet, submit a job with `StartJob`, poll `GetJob` (or subscribe via EventBridge) until it completes, then read Parquet results from your S3 output location. This is designed for processing many addresses in a single operation, not for real-time single-address lookups during form entry.

## When to Validate Addresses

Use address validation jobs in these scenarios:

- **Database cleansing**: Clean and standardize existing address databases in bulk
- **Data migration**: One-time address cleanup during system transitions
- **Before shipping/logistics**: Validate delivery addresses to reduce failed deliveries
- **Identity and risk workflows**: Standardize customer addresses for verification, risk assessment, and fraud prevention
- **Analytics and entity resolution**: Standardize addresses for location-based analytics, demographic analysis, and CRM deduplication
- **Regulatory reporting**: Validate patient/provider or customer addresses to meet compliance requirements

For interactive, single-address entry during a form session, use Autocomplete + GetPlace instead (see the address-input reference). Do NOT stand up a validation job on every keystroke or form submit.

## Supported Countries

Address validation supports addresses from: **United States, Canada, United Kingdom, and Australia**. The optional `Position` feature (coordinates) is available only in the United States, Canada, and Australia.

## Job Workflow

```
1. Prepare input   → Write addresses to a Parquet file in Amazon S3
2. StartJob        → Action=ValidateAddress, ExecutionRoleArn, Input/Output S3 locations
3. Track           → Poll GetJob (or listen on EventBridge) until Status is terminal
4. Retrieve        → Read Parquet result files from the S3 output location
```

Job status transitions: `Pending → Running → Completed` (or `Failed`), and `Cancelling → Cancelled` if you cancel it.

The Jobs API operations use `LocationClient` (`@aws-sdk/client-location`) with SigV4 (IAM) credentials — these are server-side/back-office operations, not API-key client-side calls.

## Input Schema

Input data MUST be Apache Parquet stored in Amazon S3 (limit: 10 GB per file, 1 GB per Parquet row-group). The schema supports free-form address lines, structured components, or a combination:

| Field                                                         | Description                                                                                                            |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `Id`                                                          | Optional per-record identifier. Mirrored in output as `Input_Id` so you can correlate results to inputs.               |
| `AddressLines_1` … `AddressLines_5`                           | Free-form address lines. Put single-line input in `AddressLines_1`; order multi-line input as it would appear on mail. |
| `AddressComponents_Country`                                   | Alpha-2, alpha-3 code, or full country name.                                                                           |
| `AddressComponents_Region`                                    | State, province, or territory.                                                                                         |
| `AddressComponents_SubRegion`                                 | County or equivalent.                                                                                                  |
| `AddressComponents_Locality`                                  | City or town.                                                                                                          |
| `AddressComponents_PostalCode`                                | Postal / ZIP code.                                                                                                     |
| `AddressComponents_Street`                                    | Street name.                                                                                                           |
| `AddressComponents_AddressNumber`                             | House / building number.                                                                                               |
| `AddressComponents_Unit` / `AddressComponents_UnitDesignator` | Unit value and designator (e.g. `Apt`, `Suite`, `#`).                                                                  |

**Note**: When combining `AddressLines` with `AddressComponents`, put first-line components (`AddressNumber`, `Street`, `Unit`, `UnitDesignator`) in `AddressLines`, and last-line components (`Locality`, `Region`, `SubRegion`, `Country`, `PostalCode`) in `AddressComponents`.

Example: create a Parquet input file with PyArrow.

```python
import pyarrow as pa
import pyarrow.parquet as pq

data = [
    {"Id": "record-001", "AddressLines_1": "Pike Place", "AddressLines_2": "Apartment 4B",
     "AddressComponents_Country": "USA", "AddressComponents_PostalCode": "98101"},
    {"Id": "record-002", "AddressLines_1": "2901 E Madison St",
     "AddressComponents_Country": "USA", "AddressComponents_PostalCode": "98112"},
]

schema = pa.schema([
    ("Id", pa.string()),
    ("AddressLines_1", pa.string()),
    ("AddressLines_2", pa.string()),
    ("AddressComponents_Country", pa.string()),
    ("AddressComponents_PostalCode", pa.string()),
])

pq.write_table(pa.Table.from_pylist(data, schema=schema), "addresses.parquet")
# Upload addresses.parquet to your input S3 bucket/prefix.
```

## Starting a Validation Job

`StartJob` requires the action, an `ExecutionRoleArn` that Amazon Location assumes to read your input and write your output S3 locations, and the input/output configuration. `AdditionalFeatures` is optional.

**Request shape:**

```json
{
  "Action": "ValidateAddress",
  "Name": "customer-db-cleanup-2025-06",
  "ExecutionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/LocationServiceJobExecutionRole",
  "InputOptions": {
    "Format": "Parquet",
    "Location": "arn:aws:s3:::YOUR_INPUT_BUCKET/addresses.parquet"
  },
  "OutputOptions": {
    "Format": "Parquet",
    "Location": "arn:aws:s3:::YOUR_OUTPUT_BUCKET/results/"
  },
  "ActionOptions": {
    "ValidateAddress": {
      "AdditionalFeatures": ["Position", "CountrySpecificAttributes"]
    }
  }
}
```

**`AdditionalFeatures`** (optional, choose 1–2):

- `Position` - Return WGS 84 longitude/latitude for validated addresses. US, Canada, and Australia only; incurs additional cost.
- `CountrySpecificAttributes` - Return country-specific postal/census data (e.g. USPS carrier route and delivery point for US; Australia Post / G-NAF identifiers for Australia; Royal Mail UDPRN for UK; Canada Post record type for Canada).

**JavaScript SDK:**

```javascript
import { LocationClient, StartJobCommand } from "@aws-sdk/client-location";

// Server-side: IAM credentials from environment/role
const client = new LocationClient({ region: "us-east-1" });

const response = await client.send(
  new StartJobCommand({
    Action: "ValidateAddress",
    Name: "customer-db-cleanup-2025-06",
    ExecutionRoleArn:
      "arn:aws:iam::YOUR_ACCOUNT_ID:role/LocationServiceJobExecutionRole",
    InputOptions: {
      Format: "Parquet",
      Location: "arn:aws:s3:::YOUR_INPUT_BUCKET/addresses.parquet",
    },
    OutputOptions: {
      Format: "Parquet",
      Location: "arn:aws:s3:::YOUR_OUTPUT_BUCKET/results/",
    },
    ActionOptions: {
      ValidateAddress: { AdditionalFeatures: ["Position"] },
    },
  }),
);

// Response: { JobId, JobArn, Status: "Pending", CreatedAt }
console.log("Started job:", response.JobId, response.Status);
```

**AWS CLI:**

```bash
aws location start-job \
  --action ValidateAddress \
  --execution-role-arn "arn:aws:iam::YOUR_ACCOUNT_ID:role/LocationServiceJobExecutionRole" \
  --input-options Location=arn:aws:s3:::YOUR_INPUT_BUCKET/addresses.parquet,Format=Parquet \
  --output-options Location=arn:aws:s3:::YOUR_OUTPUT_BUCKET/results/,Format=Parquet \
  --action-options '{"ValidateAddress":{"AdditionalFeatures":["Position"]}}' \
  --region us-east-1
```

The `ExecutionRoleArn` MUST be an IAM role in the same account, with permission to read the input bucket and write the output bucket. Amazon Location assumes it during processing, so you do not pass long-term credentials for S3 access.

## Tracking a Job

Poll `GetJob` with the `JobId` until `Status` is terminal (`Completed`, `Failed`, or `Cancelled`). For event-driven workflows, subscribe to job status changes via Amazon EventBridge instead of polling.

```javascript
import { GetJobCommand } from "@aws-sdk/client-location";

async function waitForJob(client, jobId) {
  const terminal = new Set(["Completed", "Failed", "Cancelled"]);
  while (true) {
    const job = await client.send(new GetJobCommand({ JobId: jobId }));
    if (terminal.has(job.Status)) return job;
    // Back off between polls; jobs are asynchronous and may run for a while.
    await new Promise((r) => setTimeout(r, 30000));
  }
}

const job = await waitForJob(client, jobId);
if (job.Status === "Failed") {
  // GetJob returns Error.Code and Error.Messages for failed jobs
  console.error("Job failed:", job.Error?.Code, job.Error?.Messages);
} else if (job.Status === "Completed") {
  // Results are in the OutputOptions.Location S3 prefix
  console.log("Results at:", job.OutputOptions.Location);
}
```

`GetJob` also returns the full job configuration (`Action`, `ActionOptions`, `ExecutionRoleArn`, `InputOptions`, `OutputOptions`), timestamps (`CreatedAt`, `UpdatedAt`, `EndedAt`), and `Error` details if it failed.

## Interpreting Results

When a job completes, read the Parquet result files from the S3 output prefix. Output **preserves all input fields with an `Input_` prefix** (so `Id` → `Input_Id`) and adds `Output_`-prefixed result fields. Records that failed to process include `ErrorType` and `ErrorMessage`.

**Overall verdict** (per record):

- `Output_ValidationResults_MatchConfidence` - `High`, `MediumHigh`, `Medium`, `MediumLow`, or `Low`
- `Output_ValidationResults_MatchConfidenceScore` - Precise score from 0 to 1.0 (1.0 = perfect match)
- `Output_ValidationResults_ValidationGranularity` - How deep the match validated:
  - `Premise` - Validated to the address-number level
  - `Street` - Validated to the street level
  - `LocalityAndPostalCode` - Locality, postal code, and country validated
  - `Locality` - Locality and country validated

**Standardized address** (`Output_Address_*` and `Output_AddressLines_*`): canonical, postal-formatted components — `Output_Address_Label`, `Output_Address_Street`, `Output_Address_AddressNumber`, `Output_Address_Locality`, `Output_Address_Region_Code`/`_Name`, `Output_Address_PostalCode`, country codes, secondary-address (unit/floor) components, and per-line output.

**Delivery indicators**: `Output_AddressMetadata_DeliveryIndicators_Mailable` and `_Locatable` (`true`/`false`).

**Per-component status**: for each component (`Country`, `Region`, `Locality`, `Street`, `AddressNumber`, `PostalCodeDetails_Base`, unit, floor, …) there is a `_Status` and `_StatusDetail`:

- `_Status`: `Validated` or `Unconfirmed`
- `_StatusDetail`: `Exact` (validated unchanged), `Corrected` (fixed from reference data), `Appended` (added from reference data), `Alias` (validated via alias), `StandardizedNoMatch` (parsed/standardized but not found), `OutOfRange` (e.g. address number outside known range), `NotFound` (empty or not found)

**Optional feature output**: `Output_Position_Longitude`/`_Latitude` (if `Position` requested) and `Output_CountrySpecificAttributes_*` (if `CountrySpecificAttributes` requested).

```javascript
// After reading a result record (e.g. via a Parquet reader):
function summarizeRecord(rec) {
  return {
    inputId: rec.Input_Id,
    confidence: rec.Output_ValidationResults_MatchConfidence,
    score: rec.Output_ValidationResults_MatchConfidenceScore,
    granularity: rec.Output_ValidationResults_ValidationGranularity,
    standardized: rec.Output_Address_Label,
    mailable: rec.Output_AddressMetadata_DeliveryIndicators_Mailable,
    coordinates: rec.Output_Position_Longitude
      ? {
          lon: rec.Output_Position_Longitude,
          lat: rec.Output_Position_Latitude,
        }
      : null,
    error: rec.ErrorType ? rec.ErrorMessage : null,
  };
}
```

## Handling Partial Matches

Some addresses come back with lower `MatchConfidence` and coarser `ValidationGranularity`. Use the overall verdict together with per-component `Status`/`StatusDetail` to decide whether to accept, correct, or reject each record:

- **Accept**: `MatchConfidence` is `High`/`MediumHigh`, `ValidationGranularity` is `Premise` (or `Street` if street-level is sufficient), delivery indicators are `Mailable`, and components are `Validated` with `StatusDetail` of `Exact`/`Corrected`/`Alias`/`Appended`. Store the standardized `Output_*` values.
- **Correct / review**: Medium confidence, or key components `Unconfirmed` with `StandardizedNoMatch` or `OutOfRange` (e.g. a valid street but an out-of-range house number). Route these to a review queue or attempt a corrected re-submission.
- **Reject / re-collect**: `Low` confidence, `Locality`-only granularity, `NotFound` on street/address number, or not `Mailable`. Ask the source (or user) for a corrected address.

Prefer the standardized `Output_*` components over the raw input when a record is accepted, and record the confidence/granularity alongside the stored address for auditability.

```javascript
function triage(rec) {
  const conf = rec.Output_ValidationResults_MatchConfidence;
  const gran = rec.Output_ValidationResults_ValidationGranularity;
  const mailable = rec.Output_AddressMetadata_DeliveryIndicators_Mailable;

  if (
    (conf === "High" || conf === "MediumHigh") &&
    gran === "Premise" &&
    mailable
  ) {
    return "accept";
  }
  if (conf === "Low" || gran === "Locality" || !mailable) {
    return "reject";
  }
  return "review";
}
```

## Listing and Canceling Jobs

- **`ListJobs`** - Enumerate your jobs and their statuses (supports filtering and pagination).
- **`CancelJob`** - Cancel a job that is `Pending` or `Running`; it transitions through `Cancelling` to `Cancelled`.

```javascript
import { ListJobsCommand, CancelJobCommand } from "@aws-sdk/client-location";

const { Entries } = await client.send(new ListJobsCommand({}));
Entries.forEach((j) => console.log(j.JobId, j.Status, j.CreatedAt));

await client.send(new CancelJobCommand({ JobId: jobId }));
```

## Error Handling

- **Job-submission errors** (`StartJob`): `ValidationException` (bad request / input constraints, including the 10 GB per-file and 1 GB per-row-group limits), `AccessDeniedException` (caller or execution role lacks permission), `ThrottlingException` (retry with backoff; `StartJob` is rate-limited), `InternalServerException`.
- **Job-lookup errors** (`GetJob`): `ResourceNotFoundException` if the `JobId` does not exist.
- **Failed jobs**: a job can reach `Status: Failed` after starting successfully. Call `GetJob` and read `Error.Code` and `Error.Messages` for the cause.
- **Per-record errors**: individual records that could not be processed carry `ErrorType`/`ErrorMessage` in the output file while the rest of the job succeeds. Always scan output for these.
- **Common setup mistake**: the `ExecutionRoleArn` must exist in the same account and grant read on the input bucket and write on the output bucket, or the job fails at S3 access.

## Pricing

Address validation is billed as a Jobs API operation, priced per record processed. The optional `Position` feature incurs additional cost and is available only in the US, Canada, and Australia. Review the [Amazon Location Service pricing page](https://aws.amazon.com/location/pricing/) and the Jobs pricing section of the developer guide before running large jobs.

## Best Practices

### Choosing the right tool

- **Use the Jobs API for validation**: `StartJob` with Action `ValidateAddress` is the address-validation API. Do NOT substitute Geocode, `SearchText`, or `SearchPlaceIndexForText` — those geocode/search and return coordinates or places, not a validation verdict.
- **Use Autocomplete + GetPlace for interactive entry**: for a live form, help users pick a real address as they type (see address-input) rather than running a job per submission.

### Input and jobs

- **Batch generously**: the Jobs API is built for bulk — process thousands to millions of addresses per job rather than many tiny jobs.
- **Respect file limits**: 10 GB per Parquet file, 1 GB per row-group; split larger datasets across files.
- **Keep `Id` on every record**: it comes back as `Input_Id`, which is how you correlate output to input.
- **Set `Name`**: name jobs meaningfully so `ListJobs` and audits stay readable.

### Results and data quality

- **Store the standardized components**: prefer `Output_*` values over raw input for accepted records.
- **Record the verdict**: persist `MatchConfidence`, `MatchConfidenceScore`, and `ValidationGranularity` alongside the address for auditability and downstream triage.
- **Handle partial matches explicitly**: use per-component `Status`/`StatusDetail` to accept, review, or reject — don't treat every completed record as valid.
- **Request only the features you need**: `Position` and `CountrySpecificAttributes` add cost; request them only when used.

### Security and operations

- **Least-privilege execution role**: scope the `ExecutionRoleArn` to only the specific input/output buckets and prefixes.
- **Prefer EventBridge over tight polling**: for long-running jobs, subscribe to status changes instead of polling `GetJob` aggressively.
- **Retry throttling with backoff**: `StartJob` is rate-limited; use exponential backoff on `ThrottlingException`.
