# Example prompts

Once `docling` is registered as an MCP server in your client (Claude
Desktop, LM Studio, or any MCP-compatible agent), these are representative
prompts for what it can do.

## Convert a document

```
Convert the PDF document at <path-or-URL> into a DoclingDocument and
return its document-key.
```

The tool converts the document once and caches it server-side under a
`document_key`; follow-up prompts in the same session can reference that
key (e.g. "now export that document to Markdown") without re-converting.

## Generate a new document

```
I want you to write a Docling document. First create it by invoking
`create_new_docling_document`. Then add a title (`add_title_to_docling_document`)
and iteratively add section headings and paragraphs. For lists, open a list
(`open_list_in_docling_document`), add items (`add_listitem_to_list_in_docling_document`),
then close it (`close_list_in_docling_document`).

Check your progress with `export_docling_document_to_markdown`. When done,
save the document and give me the file path.

The document should summarize the deployment options in this repo's
docling-serve/ and serverless-api-example/ quickstarts.
```

## RAG over a document (with the `llama-stack-rag` toolgroup enabled)

```
Convert the document at <path> and load it into the Llama Stack vector
database. Then answer: <your question about the document>.
```

Requires launching the server with the `llama-stack-rag` toolgroup and
`DOCLING_MCP_LLS_URL` pointed at your Llama Stack distribution — see
`../../rag-via-ogx-example/` for the non-agentic version of the same flow.
