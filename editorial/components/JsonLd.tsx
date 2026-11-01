type JsonLdProps = {
  data: Record<string, unknown> | Record<string, unknown>[];
};

// one script per blob — array roots make some parsers choke on @context
export function JsonLd({ data }: JsonLdProps) {
  const items = Array.isArray(data) ? data : [data];

  return (
    <>
      {items.map((item, index) => (
        <script
          key={index}
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(item) }}
        />
      ))}
    </>
  );
}
